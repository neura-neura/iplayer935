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
#define REPORT_PATH "Documents/diagnostics.json"
#define MAX_REPORT_SIZE (1024U * 1024U)

static void fail(const char *message) {
    fprintf(stderr, "%s\n", message);
}

static void fail_house_arrest_result(plist_t result) {
    plist_t error_node = result ? plist_dict_get_item(result, "Error") : NULL;
    char *value = NULL;
    if (error_node && plist_get_node_type(error_node) == PLIST_STRING) {
        plist_get_string_val(error_node, &value);
    }
    if (value && *value) {
        fprintf(stderr, "The device refused access to the app's Documents container (%s).\n", value);
    } else {
        fail("The device did not confirm access to the app's Documents container.");
    }
    free(value);
}

int main(int argc, char **argv) {
    idevice_t device = NULL;
    lockdownd_client_t lockdown = NULL;
    house_arrest_client_t house = NULL;
    afc_client_t afc = NULL;
    plist_t result = NULL;
    uint64_t file_handle = 0;
    int exit_status = 1;
    const char *udid = NULL;

    int arg = 1;
    const char *report_path = REPORT_PATH;
    if (arg < argc && strcmp(argv[arg], "--preparation") == 0) {
        report_path = "Documents/preparation.json";
        arg++;
    }
    if (argc - arg > 1) {
        fail("Usage: device-report [--preparation] [UDID]");
        return 2;
    }
    if (arg < argc) udid = argv[arg];

    if (idevice_new(&device, udid) != IDEVICE_E_SUCCESS) {
        fail("Could not connect to an iOS device.");
        goto cleanup;
    }
    if (lockdownd_client_new_with_handshake(device, &lockdown, "iplayer935-device-report") != LOCKDOWN_E_SUCCESS) {
        fail("Could not establish a trusted device session.");
        goto cleanup;
    }
    if (house_arrest_client_start_service(device, &house, "iplayer935-device-report") != HOUSE_ARREST_E_SUCCESS) {
        fail("Could not open the app's Documents container.");
        goto cleanup;
    }
    if (house_arrest_send_command(house, "VendDocuments", APP_ID) != HOUSE_ARREST_E_SUCCESS ||
        house_arrest_get_result(house, &result) != HOUSE_ARREST_E_SUCCESS) {
        fail("Could not request the app's Documents container.");
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
        fail("Could not access the app's Documents files.");
        goto cleanup;
    }
    if (afc_file_open(afc, report_path, AFC_FOPEN_RDONLY, &file_handle) != AFC_E_SUCCESS) {
        fail("The app diagnostic report is not available yet.");
        goto cleanup;
    }

    size_t capacity = 4096;
    size_t length = 0;
    char *contents = malloc(capacity + 1);
    if (!contents) {
        fail("Could not allocate a report buffer.");
        goto cleanup;
    }
    for (;;) {
        if (length == MAX_REPORT_SIZE) {
            char extra_byte = 0;
            uint32_t extra_count = 0;
            if (afc_file_read(afc, file_handle, &extra_byte, 1, &extra_count) != AFC_E_SUCCESS || extra_count != 0) {
                free(contents);
                fail("The diagnostic report is larger than expected.");
                goto cleanup;
            }
            break;
        }
        if (length == capacity) {
            size_t next = capacity * 2;
            if (next > MAX_REPORT_SIZE) next = MAX_REPORT_SIZE;
            char *grown = realloc(contents, next + 1);
            if (!grown) {
                free(contents);
                fail("Could not grow the report buffer.");
                goto cleanup;
            }
            contents = grown;
            capacity = next;
        }
        uint32_t bytes_read = 0;
        uint32_t request = (uint32_t)(capacity - length);
        afc_error_t read_status = afc_file_read(afc, file_handle, contents + length, request, &bytes_read);
        if (read_status != AFC_E_SUCCESS) {
            free(contents);
            fail("Could not read the app diagnostic report.");
            goto cleanup;
        }
        if (bytes_read == 0) break;
        length += bytes_read;
    }
    contents[length] = '\0';
    plist_t parsed_report = NULL;
    if (length == 0 || memchr(contents, '\0', length) != NULL ||
        plist_from_json(contents, (uint32_t)length, &parsed_report) != PLIST_ERR_SUCCESS ||
        !parsed_report || plist_get_node_type(parsed_report) != PLIST_DICT) {
        if (parsed_report) plist_free(parsed_report);
        free(contents);
        fail("The app diagnostic report is empty or malformed.");
        goto cleanup;
    }
    plist_free(parsed_report);

    if (afc_file_close(afc, file_handle) != AFC_E_SUCCESS) {
        file_handle = 0;
        free(contents);
        fail("Could not close the app diagnostic report.");
        goto cleanup;
    }
    file_handle = 0;
    if (fwrite(contents, 1, length, stdout) != length || fputc('\n', stdout) == EOF) {
        free(contents);
        fail("Could not print the app diagnostic report.");
        goto cleanup;
    }
    free(contents);
    exit_status = 0;

cleanup:
    if (file_handle && afc) afc_file_close(afc, file_handle);
    if (afc) afc_client_free(afc);
    if (result) plist_free(result);
    if (house) house_arrest_client_free(house);
    if (lockdown) lockdownd_client_free(lockdown);
    if (device) idevice_free(device);
    return exit_status;
}
