#include <stdint.h>

int32_t used_function(void) { return 42; }

/* Large enough that dropping it is visible in the library size. */
const char unused_blob[1 << 20] = {1};

int32_t unused_function(void) { return unused_blob[0]; }
