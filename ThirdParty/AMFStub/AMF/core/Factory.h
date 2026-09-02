//
//  Factory.h
//  AMF stub
//
//  FFmpeg's <Libavutil/hwcontext_amf.h> is part of the framework's umbrella
//  header, so importing Libavutil (or anything that depends on it) makes
//  clang parse it — and it includes AMD's Windows-only AMF SDK headers,
//  which the MPVKit binary distribution doesn't ship. AMF is a Windows GPU
//  runtime and is unreachable on Apple platforms, so nothing here is ever
//  called; these declarations exist only so the module can be built.
//
#ifndef AMF_STUB_CORE_FACTORY_H
#define AMF_STUB_CORE_FACTORY_H

typedef struct AMFFactory AMFFactory;

typedef enum AMF_MEMORY_TYPE {
    AMF_MEMORY_UNKNOWN = 0
} AMF_MEMORY_TYPE;

typedef enum AMF_SURFACE_FORMAT {
    AMF_SURFACE_UNKNOWN = 0
} AMF_SURFACE_FORMAT;

#endif
