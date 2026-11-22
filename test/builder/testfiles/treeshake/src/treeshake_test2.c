#include <stdint.h>

int32_t used_function2(void) { return 42; }

/* Large enough that dropping it is visible in the library size. */
const char unused_blob2[1 << 20] = {1};

int32_t unused_function2(void) { return unused_blob2[0]; }
