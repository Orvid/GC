/++
 + 
 + 
 + 
 + Macros:
 + ERROR = <div class="gc_error">$0</div>
 + TODO = <span class="gc_todo" style="background: #FFFF00">$0</span>
 + CLARIFY = <span class="gc_clarify" style="background: #DDDDDD">$0</span>
 + IMPLEMENTATION_DETAIL = <div class="gc_impl_detail" style="background: #00A0FF">$0</div>
 + 
 + LREF = <span class="crossreference" style="color: blue"><u>$0</u></span>
 +/
module core.gc;

GC gc = null;

// TODO: Define these correctly
class DisposalError { }
class FreeOwnershipError { }
class MemoryAlreadyOwnedError { }
alias tid_t = size_t;

/++
 + This is the core of the GC.
 +/
final class GC
{
public:
	// TODO: addRoot
	
	// TODO: addRootRange
	
	// TODO: removeRoot
	
	// TODO: removeRootRange
	
	// TODO: minimize
	
	/++
	 + Ensure that an _allocation will not be moved by a compacting
	 + allocator during a collection. 
	 + 
	 + For each invocation of this method referencing the same 
	 + _allocation, a call to $(LREF unpinAllocation) must be 
	 + performed in order to allow the underlying allocator to $(CLARIFY once
	 + again move the _allocation).
	 + 
	 + Params:
	 + allocation = A potentially interior pointer to the _allocation to pin.
	 + 
	 + Note:
	 + This will not prevent an _allocation from being collected; 
	 + for that use $(LREF addRoot).
	 + This also will not prevent it from being copied by a call
	 + to $(TODO realloc/extend), $(CLARIFY as it is assumed that the caller
	 + of those methods will update whatever references to the 
	 + _allocation are required).
	 + 
	 + Errors:
	 + $(ERROR It is an error to call this with a pointer to
	 + memory that was either not allocated by the GC,
	 + or else was already freed by the GC.)
	 + $(ERROR It is an error for a pinned _allocation which is
	 + not a root to have no living references.)
	 +/
	void pinAllocation(void* allocation);

	/++
	 + Provided that this method has been called once for every call
	 + to $(LREF pinAllocation) referencing the same _allocation, $(CLARIFY this
	 + will tell a compacting allocator that it is allowed to move the
	 + _allocation again).
	 + 
	 + Params:
	 + allocation = A potentially interior pointer to the _allocation to unpin.
	 + 
	 + Errors:
	 + $(ERROR It is an error to call this with a pointer to
	 + memory that was either not allocated by the GC, or else
	 + was already freed by the GC.)
	 +/
	void unpinAllocation(void* allocation);

	/++
	 + This method tells the GC to neither stop, nor scan the
	 + specified thread during a collection.
	 + 
	 + An example of a thread that would be suitable to being
	 + marked as not scanned would be an external thread that
	 + does only manual memory management, never allocating 
	 + through the GC, and will neither access or modify any
	 + allocations created through the GC that have not been
	 + added as roots.
	 + 
	 + Params:
	 + threadID = The ID of the thread to ignore when performing a collection.
	 + 
	 + Implementation_Details:
	 + $(IMPLEMENTATION_DETAIL This will be one of the instances
	 + of dynamic code-gen with a fallback for unsupported platforms.
	 + Due to the fact there should only be a small number of threads 
	 + being ignored by the GC, we will statically expand all thread 
	 + IDs into pairs of cmp & setne instructions, as this will eliminate
	 + all possible cases where the CPU could mispredict a branch or
	 + even a return when checking to see if a thread is ignored.)
	 +/
	void ignoreThread(tid_t threadID);

	// TODO: unIgnoreThread

	/++
	 + This method determines which allocator, if any owns allocation,
	 + and will invoke that allocator's $(LREF markAsReferenced) method,
	 + passing allocation as-is.
	 + 
	 + Params:
	 + allocation = A potentially interior pointer to a potential GC allocation.
	 + 
	 + Errors:
	 + $(ERROR It is an error to call this method with a null allocation.)
	 +/
	void markAsReferenced(void* allocation);

	/++
	 + This will check to see if an _allocation needs to be
	 + finalized, and if it does, add it to the finalization
	 + pool.
	 + 
	 + Params:
	 + allocation = The _allocation to potentially finalize.
	 + typeInfo = The $(LREF TypeInfo) representing the type
	 +            of allocation.
	 + 
	 + Returns:
	 + If true, then allocation has no finalizer to call. This means
	 + that the allocator that called this is allowed to immediately
	 + free the memory used by this allocation.
	 + 
	 + If false, then the allocator that calls this must not mark 
	 + the memory used by allocation as free, and instead must ensure
	 + that allocation is not freed. It must also ensure that allocation
	 + is only ever passed to this method once, otherwise multi-finalization
	 + will occur.
	 +/
	bool finalize(void* allocation, immutable TypeInfo typeInfo);

	/++
	 + This will determine which allocator, if any, owns allocation
	 + and invokes that allocator's $(LREF markAsFinalized) method
	 + passing allocation as-is.
	 + 
	 + Notes:
	 + This method $(B $(U MUST NOT)) be called from user code,
	 + nor should it be called by the GC; instead it is to only
	 + be called by the prologue generated for finalizers.
	 + 
	 + Params:
	 + allocation = The potentially GC-owned _allocation to mark 
	 +              as finalized.
	 + 
	 + TODO:
	 + My original design had this return a bool for successfull
	 + marking as finalized; Why?
	 +/
	void markAsFinalized(void* allocation);

	/++
	 + Release the page of memory allocated to a GC _allocator.
	 + 
	 + The _allocator being released is responsible for ensuring
	 + that all allocations it owns have been properly finalized
	 + and are indeed free before passing itself to this. It is
	 + not guaranteed that the memory owned by the _allocator will
	 + be immediately freed, it may be cached for later use.
	 + 
	 + TODO:
	 + This method may need to go away
	 +/
	void releaseAllocator(Allocator* allocator);

	// allocate

	// allocateArray

	// free

	void collect();

	/++
	 + This method will block the invoking thread until all
	 + pending finalizers have been invoked.
	 + 
	 + Note:
	 + It is likely that the invoking thread will be used 
	 + to invoke some of the pending finalizers, so it should
	 + not be assumed that a thread calling this method will
	 + sleep until all finalizers are invoked.
	 +/
	void waitForPendingFinalizers();

	/++
	 + This method will tell the GC that the specified 
	 + _allocator should be assumed to own the specified block
	 + of memory, and any references to the block of memory
	 + should be handled by allocator.
	 + 
	 + Notes:
	 + It is permitted to pass the same location in multiple times
	 + with different lengths, in which case the last length passed
	 + in is assumed to be the current _length, however allocator must
	 + be the exact same. This is done in order to allow allocators
	 + that succeed in allocating contigious blocks of memory to be
	 + looked up as effeciently as is possible.
	 + 
	 + Params:
	 + allocator = The _allocator to mark as owning the specified
	 +             block of memory.
	 + location = A pointer to the start of the block of memory to
	 +            take ownership of.
	 + length = The _length, in bytes, of the block of memory to take
	 +          ownership of.
	 + 
	 + Throws:
	 + MemoryAlreadyOwnedError if the block of memory that was passed in
	 + was already owned by another _allocator, or else if the block of 
	 + memory overlaps with another owned block of memory.
	 +/
	void takeOwnership(Allocator* allocator, void* location, size_t length);

	void releaseOwnership(void* location);
	
	void delegate(DisposalError error) onDisposalError;
	void delegate(FreeOwnershipError error) onFreeOwnershipError;
	void delegate(MemoryAlreadyOwnedError error) onMemoryAlreadyOwnedError;
	// TODO: Once the design for this is complete, add the right params.
	void delegate() onCollect;
	
	bool asyncSweepEnabled = true;
	
@property:
	bool enabled() { return collectingEnabled; }
	
private:
	bool collectingEnabled = false;
}

struct Allocator
{
public:
	ptrdiff_t largestAvailableAllocation;
	void function(void* possibleAllocation) markAsReferenced;
	void* function(immutable TypeInfo typeInfo) allocate;
	void* function(size_t allocationSize, immutable TypeInfo elementTypeInfo) allocateArray;
	size_t function() sweep;
	void function(void* allocation) free;
	bool function(void* allocation) markAsFinalized;
	
private:
}