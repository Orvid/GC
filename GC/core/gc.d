/++
 + <link href="GCDocumentationStyle.css" media="all" rel="stylesheet" type="text/css" />
 + 
 + TODO:
 + $(UL
 +   $(LI Global field name - "_gc" or "GC"? )
 +   $(LI Determine the exact needs of the new set of TypeInfo classes. )
 +   $(LI Allocator free - inner blocks? <- No idea what I meant here )
 +   $(LI init/shutdown API - need to be global )
 +   $(LI Ensure that all references to "allocator" in the documentation
 +        refer to the $(LREF Allocator) structure.
 +   )
 +   $(LI Aligned allocation )
 +   $(LI Optional generation of scanning code rather than bitmaps? If so,
 +        $(B $(U MUST)) be shared globally, perhaps by representing the
 +        bitmap as a base64-esqu symbol name?
 +   )
 +   $(LI stopIgnoringThread? )
 +   $(LI Look at destructor handling again, original design failed to
 +        account for user attempts to invoke the destructor of a non-GC
 +        allocation.
 +   )
 +   $(LI Change the way allocators are setup - Each allocator no longer
 +        owns just one page, may own many pages.
 +   )
 +   $(LI Reserve & (extend &| realloc) API )
 +   $(LI Add a way to obtain information about an allocation:
 +        $(UL
 +          $(LI Is an inner slice? )
 +          $(LI Total size? )
 +          $(LI Base pointer? )
 +          $(LI Extendable amount? )
 +        )
 +   )
 +   $(LI Decide whether to move all settings into an inner structure
 +        when making the settings into properties, due to the fact
 +        that some settings require other settings to be set, and to
 +        avoid causing issues with the GC, due to the fact it may
 +        attempt to do something modified by a setting while the user
 +        is still setting all the settings they wanted, the order that
 +        the other settings are set is crucial to the correct functioning
 +        of the GC.
 +   )
 + )
 + 
 + Goals:
 + $(UL
 +   $(LI $(B Speed) - Above all, the GC needs to be fast, if this means that some code
 +                     will need to be dynamically generated to avoid branch mispredictions,
 +                     so be it.
 +   )
 +   $(LI $(B Minimize Impact) - The GC needs to strive to achieve the minimum possible impact
 +                               on user code by using strategies such as concurrent marking
 +                               and preemptive collections.
 +   )
 +   $(LI $(B Extensible) - The GC needs to be able to coexist both peacefully, and cleanly,
 +                          with Andrei's allocators.
 +   )
 + )
 + 
 + Constraints:
 + $(UL
 +   $(LI While it is allowed to change the internal API of the GC drastically, and
 +        silently, it must be a taboo to make a silent breaking change for user code.
 +        It is however perfectly allowed to make a nice loud breaking change for user
 +        code.
 +   )
 +   $(LI While grammar extensions are welcome, grammar changes are heavily discouraged. )
 + )
 + 
 + Term_Notes:
 + $(UL
 +   $(LI In the scope of this document, $(B finalizers) and $(B destructors)
 +        are used interchangeably to refer to the same thing. No distinction
 +        is made in terminology between heap and stack allocated value finalization.
 +   )
 +   $(LI Unless otherwise obvious, the term $(B allocator) refers to
 +        GC allocators.
 +   )
 + )
 + 
 + Major_Differences:
 + $(UL
 +   $(LI There is no way to allocate initialized memory; instead the
 +        caller is responsible for initializing the memory.
 +   )
 +   $(LI Due to the need to be able to work with a unified type info
 +        interface for structs, delegates, arrays, classes, pointers,
 +        etc., the current $(LREF TypeInfo) classes have been completely
 +        re-written from the ground up.
 +   )
 +   $(LI All allocations are guarenteed to have their finalizers called
 +        before the program exits, provided that the program is not
 +        terminated abnormally, such as by a segfault, an unhandled 
 +        $(LREF Exception), or the OS killing the process. 
 +        $(IMPLEMENTATION_DETAIL The last few (up to the number of cores - 1)
 +        threads left running may be hijacked to run any remaining finalizers
 +        before they are allowed to exit along with the main thread.)
 +   )
 +   $(LI Allocations and exceptions in finalizers are allowed, however
 +        please not that exceptions will trigger a fatal error 
 +        $(TODO unless a user-defined handler is set).
 +   )
 +   $(LI Finalizers for heap-allocated structs will be invoked. )
 +   $(LI Destructors will have 2 possible places in the method where
 +        they can start, the first makes a call to $(LREF markFinalized)
 +        and then falls through to the second place, which is what a
 +        call to a destructor on a stack-allocated value will call.
 +   )
 + )
 + 
 + Concessions_Made:
 + $(UL
 +   $(LI Compacting will not be supported with the current design. It
 +        is feasible to modify the API sometime in the future, due to
 +        the extremely limited amount of code that would break, however
 +        the time investment required for the design is currently better
 +        spent designing the core of the GC that will actually be used.
 +        The API does however take the steps necessary to allow user
 +        code to be written with compacting in mind. Please note that
 +        while the pinning API will currently do absolutely nothing, 
 +        that may be changed in the future, and user code should be
 +        written under the assumption that the pinning API does indeed
 +        function, and is required.
 +   )
 + )
 +        
 + 
 + Macros:
 + ERROR = <div class="gc_error">$0</div>
 + TODO = <span class="gc_todo">$0</span>
 + CLARIFY = <span class="gc_clarify">$0</span>
 + IMPLEMENTATION_DETAIL = <div class="gc_impl_detail">$0</div>
 + 
 + LREF = <span class="crossreference"><u>$0</u></span>
 +/
module core.gc;

GC gc = null;

// TODO: Define these correctly
final class DisposalError : Error { this() { super("An exception was thrown while disposing of an object"); } }
final class FreeOwnershipError : Error { this() { super("TODO: DESCRIBE ME"); } }
final class MemoryAlreadyOwnedError : Error { this() { super("TODO: DESCRIBE ME"); } }
alias tid_t = size_t;

/++
 + This is the core of the GC.
 + 
 + It manages the interaction with the OS, freeing empty pages,
 + when to collect, $(TODO and if a precise or conservative
 + collection should be performed). It is also the only part of
 + the GC that normal D code will be interacting with. The core
 + of the GC here is entirely non-locking, instead using CAS or
 + dirty-read logic. While this non-locking design is not required
 + of $(LREF Allocator) implementations, it is heavily preferred.
 +/
final class GC
{
public:
	// TODO: addRoot
	
	// TODO: addRootRange
	
	// TODO: removeRoot
	
	// TODO: removeRootRange
	
	// TODO: minimize - return all free pages to OS
	
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

	// TODO: allocate

	// TODO: allocateArray

	// TODO: free

	/++
	 + This method will trigger a full collection, and will block
	 + the invoking thread until both the mark and sweep phases
	 + have completed. If a truely complete collection is required,
	 + and there are a large number of objects requiring finalization,
	 + such as when changing maps in a game, it is suggested to do:
	 + ----------
	 + GC.collect();
	 + GC.waitForPendingFinalizers();
	 + GC.collect();
	 + ----------
	 + This allows the allocations with finalizers to also be freed.
	 + It is not recommended for non-finalizer heavy code to do this,
	 + as it will trigger 2 full collections.
	 +/
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
	 + This method is used to tell the GC that the specified
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

	/++
	 + This method is used to tell the GC that the previously
	 + provided allocator owns pointers to values at location.
	 + 
	 + Notes:
	 + Allocator implementation must not return the memory to
	 + the OS until this method has returned, otherwise it creates
	 + a possible situation where another allocator was given the
	 + same block of memory before the current allocator has
	 + released ownership of it.
	 +/
	void releaseOwnership(void* location);

	/++
	 + This method is used to _enable automatic garbage collection
	 + if it has previously been disabled by a call to $(LREF disable).
	 + 
	 + It is required to call this method once for every call to
	 + $(LREF disable) in order to re-_enable the GC.
	 + 
	 + Throws:
	 + GCAlreadyEnabledError if this method is called when the GC
	 + is already enabled. This is done to prevent code which has
	 + imbalanced _enable/disable logic from silently succeeding
	 + when the GC is already enabled.
	 +/
	void enable();

	/++
	 + This method is used to _disable automatic garbage collection.
	 + 
	 + It is required to call $(LREF enable) once for every call to
	 + this in order to re-enable the GC. This is done to allow specific
	 + functions in large libraries ($(B not Phobos)) to _disable and
	 + re-enable the GC for whatever reason they wish, without causing
	 + any code invoking it, which may also have a reason to _disable
	 + the GC, to have to re-_disable the GC after calling that method.
	 +/
	void disable();


	/++
	 + This delegate is invoked when an exception occurs while calling
	 + the finalizer of an allocation. The default handler simply throws
	 + the error passed to it.
	 +/
	void delegate(DisposalError error) onDisposalError;// = &defaultErrorHandler;

	/++
	 + This delegate is invoked when an $(LREF Allocator)'s $(LREF free)
	 + method is passed a pointer to an allocation for memory not actually
	 + owned by it.
	 + 
	 + This should never happen if the GC is working correctly,
	 + however, as $(LREF Allocator)s are expected to throw this, there
	 + needs to be a way to handle it.
	 +/
	void delegate(FreeOwnershipError error) onFreeOwnershipError;// = &defaultErrorHandler;

	// TODO: Document
	void delegate(MemoryAlreadyOwnedError error) onMemoryAlreadyOwnedError;// = &defaultErrorHandler;
	// TODO: Once the design for this is complete, add the right params.
	void delegate() onCollect;


	/++
	 + If true, then the GC will perform an asynchronous sweep,
	 + allowing all non-blocked threads to continue while the sweep
	 + is occurring.
	 + 
	 + The GC will also attempt to, when applicable, unblock the
	 + thread that triggered the collection as soon as possible.
	 +/
	bool asyncSweepEnabled = true;

	/++
	 + If true, then the GC may attempt to preemptively perform
	 + a collection, in order to avoid blocking a future allocation
	 + request due to the need to run a collection pass.
	 + 
	 + TODO:
	 + Decide if this should default to true or false (currently true)
	 +/
	bool preemptiveCollectionsEnabled = true;

	/++
	 + true iff automatic garbage collection is currently _enabled
	 + and may trigger a collection rather than allocating more
	 + memory when the GC is unable to complete a request for an
	 + allocation.
	 +/
	@property bool enabled() { return collectingEnabled; }
	
private:
	bool collectingEnabled = false;

	// TODO: Set this as the default value of the fields.
	/// This is the default method used to handle all errors.
	static void defaultErrorHandler(Error error) { throw error; }
}

struct Allocator
{
public:
	void function(void* possibleAllocation) markAsReferenced;
	void* function(immutable TypeInfo typeInfo) allocate;
	void* function(size_t allocationSize, immutable TypeInfo elementTypeInfo) allocateArray;
	size_t function() sweep;
	void function(void* allocation) free;
	bool function(void* allocation) markAsFinalized;
	
private:
}