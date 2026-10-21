#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/house_arrest.h>
#include <libimobiledevice/afc.h>
#include <plist/plist.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define APP_ID "org.neura.iplayer935"
#define PREVIEW_PATH "Documents/player-preview.png"
#define MAX_PREVIEW_SIZE (4U * 1024U * 1024U)
#define PNG_SIGNATURE "\x89PNG\r\n\x1a\n"

static void fail(const char *message) {
    fprintf(stderr, "%s\n", message);
}

static void fail_house_arrest_result(plist_t result) {
    plist_t error_node = result ? plist_dict_get_item(result, "Error") : NULL;
    char *value = NULL;
    if (error_node && plist_get_node_type(error_node) == PLIST_STRING)
        plist_get_string_val(error_node, &value);
    if (value && *value)
        fprintf(stderr, "The device refused access to this app's Documents folder (%s).\n", value);
    else
        fail("The device did not confirm access to this app's Documents folder.");
    free(value);
}

int main(int argc, char **argv) {
    idevice_t device = NULL;
    lockdownd_client_t lockdown = NULL;
    house_arrest_client_t house = NULL;
    afc_client_t afc = NULL;
    plist_t result = NULL;
    uint64_t handle = 0;
    FILE *output = NULL;
    uint8_t *buffer = NULL;
    int exit_status = 1;
    const char *udid = NULL;
    const char *destination = argc >= 2 ? argv[1] : NULL;

    if (argc > 3) {
        fail("Usage: device-preview [OUTPUT_PATH [UDID]]");
        return 2;
    }
    if (argc == 3) udid = argv[2];
    if (!destination || !*destination) {
        fail("Output path is required.");
        return 2;
    }

    if (idevice_new(&device, udid) != IDEVICE_E_SUCCESS) {
        fail("Could not connect to an iOS device.");
        goto cleanup;
    }
    if (lockdownd_client_new_with_handshake(device, &lockdown, "iplayer935-device-preview") != LOCKDOWN_E_SUCCESS) {
        fail("Could not establish a trusted device session.");
        goto cleanup;
    }
    if (house_arrest_client_start_service(device, &house, "iplayer935-device-preview") != HOUSE_ARREST_E_SUCCESS) {
        fail("Could not open this app's Documents folder.");
        goto cleanup;
    }
    if (house_arrest_send_command(house, "VendDocuments", APP_ID) != HOUSE_ARREST_E_SUCCESS ||
        house_arrest_get_result(house, &result) != HOUSE_ARREST_E_SUCCESS) {
        fail("Could not request this app's Documents folder.");
        goto cleanup;
    }
    plist_t status = plist_dict_get_item(result, "Status");
    char *status_value = NULL;
    if (!status || plist_get_node_type(status) != PLIST_STRING) {
        fail_house_arrest_result(result);
        goto cleanup;
    }
    plist_get_string_val(status, &status_value);
    if (!status_value || strcmp(status_value, "Complete") != 0) {
        free(status_value);
        fail_house_arrest_result(result);
        goto cleanup;
    }
    free(status_value);
    plist_free(result);
    result = NULL;

    if (afc_client_new_from_house_arrest_client(house, &afc) != AFC_E_SUCCESS) {
        fail("Could not access this app's Documents files.");
        goto cleanup;
    }
    if (afc_file_open(afc, PREVIEW_PATH, AFC_FOPEN_RDONLY, &handle) != AFC_E_SUCCESS) {
        fail("The device preview is not available yet.");
        goto cleanup;
    }

    buffer = malloc(MAX_PREVIEW_SIZE);
    if (!buffer) {
        fail("Could not allocate a bounded preview buffer.");
        goto cleanup;
    }
    size_t length = 0;
    while (length < MAX_PREVIEW_SIZE) {
        uint32_t bytes_read = 0;
        uint32_t request = (uint32_t)(MAX_PREVIEW_SIZE - length);
        afc_error_t read_result = afc_file_read(afc, handle, (char *)buffer + length, request, &bytes_read);
        if (read_result != AFC_E_SUCCESS) {
            fail("Could not read the device preview.");
            goto cleanup;
        }
        if (bytes_read == 0) break;
        length += bytes_read;
    }
    if (length == MAX_PREVIEW_SIZE) {
        char extra = 0;
        uint32_t extra_count = 0;
        if (afc_file_read(afc, handle, &extra, 1, &extra_count) != AFC_E_SUCCESS || extra_count != 0) {
            fail("The device preview exceeds the 4 MiB size limit.");
            goto cleanup;
        }
    }
    if (length < 8 || memcmp(buffer, PNG_SIGNATURE, 8) != 0) {
        fail("The device preview is not a valid PNG file.");
        goto cleanup;
    }
    if (afc_file_close(afc, handle) != AFC_E_SUCCESS) {
        handle = 0;
        fail("Could not close the device preview.");
        goto cleanup;
    }
    handle = 0;

    output = fopen(destination, "wb");
    if (!output) {
        fail("Could not create the local preview file.");
        goto cleanup;
    }
    size_t written = fwrite(buffer, 1, length, output);
    int close_status = fclose(output);
    output = NULL;
    if (written != length || close_status != 0) {
        fail("Could not write the complete local preview file.");
        goto cleanup;
    }
    printf("Saved device preview (%zu bytes).\n", length);
    exit_status = 0;

cleanup:
    if (output) fclose(output);
    if (handle && afc) afc_file_close(afc, handle);
    free(buffer);
    if (afc) afc_client_free(afc);
    if (result) plist_free(result);
    if (house) house_arrest_client_free(house);
    if (lockdown) lockdownd_client_free(lockdown);
    if (device) idevice_free(device);
    return exit_status;
}
