# Memory

Important things to take note of and consider with dealing with the memory
boundary between host and guest in wasm.

## Key points

**The guest can only access its own memory.**
It cannot access anything outside of its sandbox. To get memory from the host to
the guest it must first be copied into the guest's memory.

**The host can access any guest's memory without copy.**
Since the host owns the memory within its guest's the host only needs to convert
the pointers from the guests memory space into its own, this is cheap.

## Takeaways

If the guest and host need to have access over memory it is best to allocate
it within the guest. This still does not allow for guests other than the one the
memory was allocated in to access such memory. Shared memory would be quite
helpful here.

Be careful about sharing host allocated memory with the guest as it is costly.

# TODO

We might be able to use the store data as a type of shared memory
