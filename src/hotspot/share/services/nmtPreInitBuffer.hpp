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

#ifndef SHARE_SERVICES_NMT_PREINIT_BUFFER_HPP
#define SHARE_SERVICES_NMT_PREINIT_BUFFER_HPP



#include "memory/allocation.hpp"
#include "utilities/debug.hpp"
#include "utilities/globalDefinitions.hpp"
#include "utilities/macros.hpp"

#if INCLUDE_NMT

class outputStream;

// The purpose of this class is to serve as a simple buffer for pre-initialization
//  C-Heap allocations.
class NMTPreInitBuffer : public AllStatic {

  ATTRIBUTE_ALIGNED(16) static const size_t buffer_size = 64 * K;

  static uint8_t _buffer[buffer_size];
  static uint8_t* _top;
  static const uint8_t* end() { return _buffer + buffer_size; }

  static void initialize();
  static bool is_initialized() { return _top != NULL; }

public:

  // Allocate s bytes from the preinit buffer. Can only be called before NMT initialization.
  // On buffer exhaustion, NMT is switched off and C-heap is returned instead (release);
  // in debug builds we assert.
  static void* allocate(size_t s, MEMFLAGS flag);

  // Reallocate an allocation originally allocated from the preinit buffer within the preinit
  // buffer.  Can only be called before NMT initialization.
  // On buffer exhaustion, NMT is switched off and C-heap is returned instead (release);
  // in debug builds we assert.
  static void* reallocate(void* old, size_t s, MEMFLAGS flag);

  // Reallocate an allocation originally allocated from the preinit buffer into the regular
  // C-heap. Can only be called *after* NMT initialization.
  static void* reallocate_to_c_heap(void* old, size_t s, MEMFLAGS flag);

  // Attempts to free a block originally allocated from the preinit buffer (only rolls
  // back top allocation).
  static void free(void* old);

  // Needs to be fast
  inline static bool contains(const void* p) {
    assert(is_initialized(), "sanity");
    return _buffer <= (uint8_t*)p &&
           (uint8_t*)p < _buffer + sizeof(_buffer);
  }

  // print a string describing the current buffer state
  static void print_state(outputStream* st);

};

#endif // INCLUDE_NMT

#endif // SHARE_SERVICES_NMT_PREINIT_BUFFER_HPP
