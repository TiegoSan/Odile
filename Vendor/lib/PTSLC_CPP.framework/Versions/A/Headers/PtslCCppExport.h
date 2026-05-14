
#ifndef PTSLC_CPP_EXPORT_H
#define PTSLC_CPP_EXPORT_H

#ifdef PTSLC_CPP_STATIC_DEFINE
#  define PTSLC_CPP_EXPORT
#  define PTSLC_CPP_NO_EXPORT
#else
#  ifndef PTSLC_CPP_EXPORT
#    ifdef PTSLC_CPP_EXPORTS
        /* We are building this library */
#      define PTSLC_CPP_EXPORT __attribute__((visibility("default")))
#    else
        /* We are using this library */
#      define PTSLC_CPP_EXPORT __attribute__((visibility("default")))
#    endif
#  endif

#  ifndef PTSLC_CPP_NO_EXPORT
#    define PTSLC_CPP_NO_EXPORT __attribute__((visibility("hidden")))
#  endif
#endif

#ifndef PTSLC_CPP_DEPRECATED
#  define PTSLC_CPP_DEPRECATED __attribute__ ((__deprecated__))
#endif

#ifndef PTSLC_CPP_DEPRECATED_EXPORT
#  define PTSLC_CPP_DEPRECATED_EXPORT PTSLC_CPP_EXPORT PTSLC_CPP_DEPRECATED
#endif

#ifndef PTSLC_CPP_DEPRECATED_NO_EXPORT
#  define PTSLC_CPP_DEPRECATED_NO_EXPORT PTSLC_CPP_NO_EXPORT PTSLC_CPP_DEPRECATED
#endif

#if 0 /* DEFINE_NO_DEPRECATED */
#  ifndef PTSLC_CPP_NO_DEPRECATED
#    define PTSLC_CPP_NO_DEPRECATED
#  endif
#endif

#endif /* PTSLC_CPP_EXPORT_H */
