#include "hbapi.h"
#include "hbapiitm.h"

#include "sshfling_launcher.h"

HB_FUNC(SSHFLINGVERSION) {
    hb_retc(sshfling_launcher_version());
}

HB_FUNC(SSHFLINGRUN) {
    PHB_ITEM arguments = hb_param(1, HB_IT_ARRAY);
    const HB_SIZE count = arguments == NULL ? 0 : hb_arrayLen(arguments);
    const char **values;
    int status;

    if (arguments == NULL) {
        hb_retni(2);
        return;
    }
    values = (const char **)hb_xgrab((count == 0 ? 1 : count) * sizeof(*values));
    for (HB_SIZE index = 0; index < count; ++index) {
        values[index] = hb_arrayGetCPtr(arguments, index + 1);
    }
    status = sshfling_launcher_run((size_t)count, values);
    hb_xfree(values);
    hb_retni(status);
}
