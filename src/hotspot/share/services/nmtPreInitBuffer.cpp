/*
 * Copyright (c) 2021 SAP SE. All rights reserved.
 * Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 *
 */

#include "precompiled.hpp"
#include "jvm_io.h"
#include "logging/log.hpp"
#include "services/memTracker.hpp"
#include "services/nmtPreInitBuffer.hpp"
#include "utilities/align.hpp"
#include "utilities/debug.hpp"
#include "utilities/globalDefinitions.hpp"
#include "utilities/macros.hpp"

// Threadedness note:
//
// The NMTPreInitBuffer is guaranteed to be used only single threaded, since its
// only used during VM initialization. However, that does not mean that its always
// the same thread, since the thread loading the hotspot - which causes the
// dynamic C++ initialization inside the hotspot to run, and allocations to happen
// - may be a different thread from the one invoking CreateJavaVM.

#if INCLUDE_NMT

#include <stdlib.h> // for raw malloc

const static size_t malloc_alignment = NOT_LP64(8) LP64_ONLY(16);

// To be able to provide at least a primitive notion of realloc, we
// need to know the block size, hence we need a small header.
struct hdr {
  size_t len;
  size_t dummy;
};

STATIC_ASSERT(sizeof(hdr) == malloc_alignment);

// Statistics
static struct {
  int allocs;
  int reallocs; int inplace_reallocs;
  int frees; int inplace_frees;
} g_stats;

static hdr* get_hdr(void* p) {
  assert(is_aligned(p, malloc_alignment), "sanity");
  return ((hdr*)p) - 1;
}

static size_t get_block_size(void* p) {
  return get_hdr(p)->len;
}

uint8_t NMTPreInitBuffer::_buffer[buffer_size] = { 0 };
uint8_t* NMTPreInitBuffer::_top = NULL;

void NMTPreInitBuffer::initialize() {
  assert(_top == NULL, "sanity");
  _top = _buffer;
}

// Allocate s bytes from the preinit buffer. Can only be called before NMT initialization.
// On buffer exhaustion, NMT is switched off and C-heap is returned instead (release);
// in debug builds we assert.
void* NMTPreInitBuffer::allocate(size_t size, MEMFLAGS flag) {

  // Initialize on very first malloc. We need to do this on demand since we cannot
  // rely on order of initialization.
  if (!is_initialized()) {
    initialize();
  }

  // We only allow this before NMT initialization.
  assert(!MemTracker::is_initialized(), "Use only pre-NMT initialization");

  // 0->1, and honor malloc alignment
  const size_t inner_size = align_up(MAX2((size_t)1, size), malloc_alignment);
  const size_t outer_size = inner_size + sizeof(hdr);

  // Buffer exhausted?
  if (_top + outer_size > end()) {
    // On pre-init buffer exhaustion, disable NMT. This will end the pre-init phase, so
    // we will not allocate from the pre-init buffer anymore. It will prevent NMT from
    // being switched on later after argument parsing, but at least it allows the VM to
    // continue.
    MemTracker::initialize(NMT_off);
    // Then, fulfill the allocation request from normal C-heap.
    return os::malloc(size, flag);
  }

  // Allocate from top.
  hdr* const new_hdr = (hdr*)_top;
  new_hdr->len = inner_size;
  uint8_t* const ret = (uint8_t*)(new_hdr + 1);
  _top += outer_size;
  assert(_top == ret + inner_size, "sanity");

  DEBUG_ONLY(::memset(ret, 0x17, inner_size));

  g_stats.allocs++;

  return ret;
}

// Reallocate an allocation originally allocated from the preinit buffer within the preinit
// buffer.  Can only be called before NMT initialization.
// On buffer exhaustion, NMT is switched off and C-heap is returned instead (release);
// in debug builds we assert.
void* NMTPreInitBuffer::reallocate(void* old, size_t size, MEMFLAGS flag) {

  assert(is_initialized(), "sanity");

  // We only allow this before NMT initialization, and only from a single thread.
  assert(!MemTracker::is_initialized(), "Use only pre-NMT initialization");

  // The old block should not be NULL and be contained in the preinit buffer.
  assert(contains(old), "sanity");

  // Note: We don't bother to implement any optimizations here (eg in-place-realloc).
  //  Chances of reallocs happening which would benefit are not high. If we start hurting
  //  we can optimize (see also free below).
  uint8_t* ret = (uint8_t*)allocate(size, flag);
  if (size > 0 && old != NULL) {
    size_t size_old = get_block_size(old);
    if (size_old > 0) {
      ::memcpy(ret, old, MIN2(size, size_old));
    }
    free(old);
  }

  g_stats.reallocs++;

  return ret;
}

// Reallocate an allocation originally allocated from the preinit buffer into the regular
// C-heap. Can only be called *after* NMT initialization.
void* NMTPreInitBuffer::reallocate_to_c_heap(void* old, size_t size, MEMFLAGS flag) {

  assert(is_initialized(), "sanity");

  // This should only be called after NMT initialization.
  assert(MemTracker::is_initialized(), "Use only post-NMT initialization");

  // The old block should not be NULL and be contained in the preinit buffer.
  assert(contains(old), "sanity");

  uint8_t* ret = NEW_C_HEAP_ARRAY(uint8_t, size, flag);
  if (size > 0 && old != NULL) {
    size_t size_old = get_block_size(old);
    if (size_old > 0) {
      ::memcpy(ret, old, MIN2(size, size_old));
    }
  }

  return ret;
}

// Attempts to free a block originally allocated from the preinit buffer (only rolls
// back top allocation).
void NMTPreInitBuffer::free(void* old) {

  assert(is_initialized(), "sanity");

  // The old block should not be NULL and be contained in the preinit buffer.
  assert(contains(old), "sanity");

  // Roll back top-of-arena-allocations...
  const size_t old_size = get_block_size(old);
  if (_top - old_size == (uint8_t*)old) {
    _top = (uint8_t*)old - sizeof(hdr);
    g_stats.inplace_frees++;
  }

  // ... otherwise just ignore. If we are really hurting, we may add some
  // form of freeblock management; but lets keep things simple for now.
  g_stats.frees++;
}

void NMTPreInitBuffer::print_state(outputStream* st) {
  st->print_cr("buffer: " PTR_FORMAT ", used: " SIZE_FORMAT ", end: " PTR_FORMAT ", stats: %d/%d(%d)/%d(%d)",
               p2i(_buffer), _top - _buffer, p2i(end()),
               g_stats.allocs,
               g_stats.reallocs, g_stats.inplace_reallocs,
               g_stats.frees, g_stats.inplace_frees);
}


#endif // INCLUDE_NMT
