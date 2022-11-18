//===--- _SwiftCxxInteroperability.h - C++ Interop support ------*- C++ -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  Defines types and support functions required by C++ bindings generated
//  by the Swift compiler that allow C++ code to call Swift APIs.
//
//===----------------------------------------------------------------------===//
#ifndef SWIFT_CXX_INTEROPERABILITY_H
#define SWIFT_CXX_INTEROPERABILITY_H

#ifdef __cplusplus

#include <cstdint>
#include <stdlib.h>
#if defined(_WIN32)
#include <malloc.h>
#endif
#if !defined(SWIFT_CALL)
# define SWIFT_CALL __attribute__((swiftcall))
#endif

// FIXME: Use always_inline, artificial.
#define SWIFT_INLINE_THUNK inline

namespace swift {
namespace _impl {

extern "C" void *_Nonnull swift_retain(void *_Nonnull) noexcept;

extern "C" void swift_release(void *_Nonnull) noexcept;

inline void *_Nonnull opaqueAlloc(size_t size, size_t align) noexcept {
#if defined(_WIN32)
  void *r = _aligned_malloc(size, align);
#else
  if (align < sizeof(void *))
    align = sizeof(void *);
  void *r = nullptr;
  int res = posix_memalign(&r, align, size);
  (void)res;
#endif
  return r;
}

inline void opaqueFree(void *_Nonnull p) noexcept {
#if defined(_WIN32)
  _aligned_free(p);
#else
  free(p);
#endif
}

/// Base class for a container for an opaque Swift value, like resilient struct.
class OpaqueStorage {
public:
  inline OpaqueStorage() noexcept : storage(nullptr) {}
  inline OpaqueStorage(size_t size, size_t alignment) noexcept
      : storage(reinterpret_cast<char *>(opaqueAlloc(size, alignment))) {}
  inline OpaqueStorage(OpaqueStorage &&other) noexcept
      : storage(other.storage) {
    other.storage = nullptr;
  }
  inline OpaqueStorage(const OpaqueStorage &) noexcept = delete;

  inline ~OpaqueStorage() noexcept {
    if (storage) {
      opaqueFree(static_cast<char *_Nonnull>(storage));
    }
  }

  void operator=(OpaqueStorage &&other) noexcept {
    auto temp = storage;
    storage = other.storage;
    other.storage = temp;
  }
  void operator=(const OpaqueStorage &) noexcept = delete;

  inline char *_Nonnull getOpaquePointer() noexcept {
    return static_cast<char *_Nonnull>(storage);
  }
  inline const char *_Nonnull getOpaquePointer() const noexcept {
    return static_cast<char *_Nonnull>(storage);
  }

private:
  char *_Nullable storage;
};

/// Base class for a Swift reference counted class value.
class RefCountedClass {
public:
  inline ~RefCountedClass() { swift_release(_opaquePointer); }
  inline RefCountedClass(const RefCountedClass &other) noexcept
      : _opaquePointer(other._opaquePointer) {
    swift_retain(_opaquePointer);
  }
  inline RefCountedClass &operator=(const RefCountedClass &other) noexcept {
    swift_retain(other._opaquePointer);
    swift_release(_opaquePointer);
    _opaquePointer = other._opaquePointer;
    return *this;
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmissing-noreturn"
  // FIXME: implement 'move'?
  inline RefCountedClass(RefCountedClass &&) noexcept { abort(); }
#pragma clang diagnostic pop

protected:
  inline RefCountedClass(void *_Nonnull ptr) noexcept : _opaquePointer(ptr) {}

private:
  void *_Nonnull _opaquePointer;
  friend class _impl_RefCountedClass;
};

class _impl_RefCountedClass {
public:
  static inline void *_Nonnull getOpaquePointer(const RefCountedClass &object) {
    return object._opaquePointer;
  }
  static inline void *_Nonnull &getOpaquePointerRef(RefCountedClass &object) {
    return object._opaquePointer;
  }
  static inline void *_Nonnull copyOpaquePointer(
      const RefCountedClass &object) {
    swift_retain(object._opaquePointer);
    return object._opaquePointer;
  }
};

} // namespace _impl

/// Swift's Int type.
using Int = ptrdiff_t;

/// Swift's UInt type.
using UInt = size_t;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++17-extensions"

/// True if the given type is a Swift type that can be used in a generic context
/// in Swift.
template <class T>
static inline const constexpr bool isUsableInGenericContext = false;

/// Returns the type metadata for the given Swift type T.
template <class T> struct TypeMetadataTrait {
  static inline void *_Nonnull getTypeMetadata();
};

namespace _impl {

/// Type trait that returns the `_impl::_impl_<T>` class type for the given
/// class T.
template <class T> struct implClassFor {
  // using type = ...;
};

/// True if the given type is a Swift value type.
template <class T> static inline const constexpr bool isValueType = false;

/// True if the given type is a Swift value type with opaque layout that can be
/// boxed.
template <class T> static inline const constexpr bool isOpaqueLayout = false;

/// True if the given type is a C++ record that was bridged to Swift, giving
/// Swift ability to work with it in a generic context.
template <class T>
static inline const constexpr bool isSwiftBridgedCxxRecord = false;

/// Returns the opaque pointer to the given value.
template <class T>
inline const void *_Nonnull getOpaquePointer(const T &value) {
  if constexpr (isOpaqueLayout<T>)
    return reinterpret_cast<const OpaqueStorage &>(value).getOpaquePointer();
  return reinterpret_cast<const void *>(&value);
}

template <class T> inline void *_Nonnull getOpaquePointer(T &value) {
  if constexpr (isOpaqueLayout<T>)
    return reinterpret_cast<OpaqueStorage &>(value).getOpaquePointer();
  return reinterpret_cast<void *>(&value);
}

} // namespace _impl

constexpr static std::size_t max(std::size_t a, std::size_t b) {
  return a > b ? a : b;
}

/// The Expected class has either an error or an value.
template<class T>
class Expected {
public:

  /// Default
  constexpr Expected() noexcept {
    new (&buffer) Error();
    has_val = false;
  }

  constexpr Expected(const swift::Error& error_val) noexcept {
    new (&buffer) Error(error_val);
    has_val = false;
  }

  constexpr Expected(const T &val) noexcept {
    new (&buffer) T(val);
    has_val = true;
  }

  /// Copy
  constexpr Expected(Expected const& other) noexcept {
    if (other.has_value())
      new (&buffer) T(other.value());
    else
      new (&buffer) Error(other.error());

    has_val = other.has_value();
  }

  /// Move
  // FIXME: Implement move semantics when move Swift values is possible
  constexpr Expected(Expected&&) noexcept { abort(); }

  ~Expected() noexcept {
    if (has_value())
      reinterpret_cast<const T *>(buffer)->~T();
    else
      reinterpret_cast<swift::Error *>(buffer)->~Error();
  }

  /// assignment
  constexpr auto operator=(Expected&& other) noexcept = delete;
  constexpr auto operator=(Expected&) noexcept = delete;

  /// For accessing T's members
  constexpr T const *_Nonnull operator->() const noexcept {
    if (!has_value())
      abort();
    return reinterpret_cast<const T *>(buffer);
  }

  constexpr T *_Nonnull operator->() noexcept {
    if (!has_value())
      abort();
    return reinterpret_cast<T *>(buffer);
  }

  /// Getting reference to T
  constexpr T const &operator*() const & noexcept {
    if (!has_value())
      abort();
    return reinterpret_cast<const T &>(buffer);
  }

  constexpr T &operator*() & noexcept {
    if (!has_value())
      abort();
    return reinterpret_cast<T &>(buffer);
  }

  constexpr explicit operator bool() const noexcept { return has_value(); }

  // Get value, if not exists abort
  constexpr T const& value() const& {
    if (!has_value())
      abort();
    return *reinterpret_cast<const T *>(buffer);
  }

  constexpr T& value() & {
    if (!has_value())
      abort();
    return *reinterpret_cast<T *>(buffer);
  }

  // Get error
  constexpr swift::Error const& error() const& {
    if (has_value())
      abort();
    return reinterpret_cast<const swift::Error&>(buffer);
  }

  constexpr swift::Error& error() & {
    if (has_value())
      abort();
    return reinterpret_cast<swift::Error&>(buffer);
  }

  constexpr bool has_value() const noexcept { return has_val; }

private:
  alignas(max(alignof(T), alignof(swift::Error))) char buffer[max(sizeof(T), sizeof(swift::Error))];
  bool has_val;
};

#pragma clang diagnostic pop

} // namespace swift
#endif

#endif // SWIFT_CXX_INTEROPERABILITY_H
