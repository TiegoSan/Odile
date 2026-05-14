#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "PTSLC_CPP::PTSLC_CPP" for configuration "Release"
set_property(TARGET PTSLC_CPP::PTSLC_CPP APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(PTSLC_CPP::PTSLC_CPP PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/./PTSLC_CPP.framework/Versions/A/PTSLC_CPP"
  IMPORTED_SONAME_RELEASE "@rpath/PTSLC_CPP.framework/Versions/A/PTSLC_CPP"
  )

list(APPEND _cmake_import_check_targets PTSLC_CPP::PTSLC_CPP )
list(APPEND _cmake_import_check_files_for_PTSLC_CPP::PTSLC_CPP "${_IMPORT_PREFIX}/./PTSLC_CPP.framework/Versions/A/PTSLC_CPP" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
