# Copyright 2022-2023 by Avid Technology, Inc.
# CONFIDENTIAL: this document contains confidential information of Avid. Do not disclose to any third party. Use of the information contained in this document is subject to an Avid SDK license.


####### Expanded from @PACKAGE_INIT@ by configure_package_config_file() #######
####### Any changes to this file will be overwritten by the next CMake run ####
####### The input file was Config.cmake.in                            ########

get_filename_component(PACKAGE_PREFIX_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../" ABSOLUTE)

macro(set_and_check _var _file)
  set(${_var} "${_file}")
  if(NOT EXISTS "${_file}")
    message(FATAL_ERROR "File or directory ${_file} referenced by variable ${_var} does not exist !")
  endif()
endmacro()

macro(check_required_components _NAME)
  foreach(comp ${${_NAME}_FIND_COMPONENTS})
    if(NOT ${_NAME}_${comp}_FOUND)
      if(${_NAME}_FIND_REQUIRED_${comp})
        set(${_NAME}_FOUND FALSE)
      endif()
    endif()
  endforeach()
endmacro()

####################################################################################

include(CMakeFindDependencyMacro)

# Include dependencies target files first as those are required for the project.
# It's not needed to include every one as this point as only the base cmake target is referenced.
file(GLOB PTSLC_CPP_CURRENT_DEPENDENCIES_TARGET_FILES "${CMAKE_CURRENT_LIST_DIR}/PTSLC_CPPDependenciesTargets-*.cmake")
foreach(f ${PTSLC_CPP_CURRENT_DEPENDENCIES_TARGET_FILES})
    message(STATUS "PTSLC_CPP: including dependencies: ${f}")
    include(${f})
endforeach()

# Include the main targets file.
include("${CMAKE_CURRENT_LIST_DIR}/PTSLC_CPPTargets.cmake")

# Because we can't distribute several build types in a single bundle (framework), provide a way to update the target thanks to CMake Targets structure.
# This allows switching Debug/Release without doing reconfigure.

unset(PTSLC_CPP_FOUND_CONFIGURATIONS_WITH_TARGETS_FILE)
unset(PTSLC_CPP_DEPENDENCIES_TARGET_DIRECTORIES)

# Only when multiple configuration types requested.
if (CMAKE_CONFIGURATION_TYPES)
    # Get already imported configurations.
    get_target_property(PTSLC_CPP_IMPORTED_CONFIGURATIONS PTSLC_CPP::PTSLC_CPP IMPORTED_CONFIGURATIONS)

    foreach(EXPECTED_CONFIGURATION IN LISTS CMAKE_CONFIGURATION_TYPES)
        message(STATUS "PTSLC_CPP: checking ${EXPECTED_CONFIGURATION} configuration")
        
        string(TOUPPER "${EXPECTED_CONFIGURATION}" EXPECTED_CONFIGURATION_UPPER)
        string(TOLOWER "${EXPECTED_CONFIGURATION}" EXPECTED_CONFIGURATION_LOWER)
        set(PTSLC_CPP_CONFIGURATION_ROOT_NAME "PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_ROOT")

        # We don't need to import again.
        set(SKIP_EXPECTED_CONFIGURATION FALSE)
        foreach(IMPORTED_CONFIGURATION IN LISTS PTSLC_CPP_IMPORTED_CONFIGURATIONS)
            string(TOLOWER "${IMPORTED_CONFIGURATION}" IMPORTED_CONFIGURATION_LOWER)
            if (EXPECTED_CONFIGURATION_LOWER STREQUAL IMPORTED_CONFIGURATION_LOWER)
                set(SKIP_EXPECTED_CONFIGURATION TRUE)
            endif()
        endforeach()

        if (SKIP_EXPECTED_CONFIGURATION)
            continue()
        endif()

        # If the e.g. PTSLC_CPP_DEBUG_ROOT is defined in the cache - try to find the targets.
        if (${PTSLC_CPP_CONFIGURATION_ROOT_NAME})
            set(PTSLC_CPP_TARGET_FILE_TO_SEARCH "PTSLC_CPPTargets-${EXPECTED_CONFIGURATION_LOWER}.cmake")
            find_file(PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_TARGETS_FILE
                "${PTSLC_CPP_TARGET_FILE_TO_SEARCH}"
                PATHS
                    "${${PTSLC_CPP_CONFIGURATION_ROOT_NAME}}/PTSLC_CPP/CMake"
                    "${${PTSLC_CPP_CONFIGURATION_ROOT_NAME}}/PTSLC_CPP.framework/Resources/CMake"
                    "${${PTSLC_CPP_CONFIGURATION_ROOT_NAME}}/CMake"
                CACHE
                NO_DEFAULT_PATH
            )

            # Maybe that configuration hasn't been built yet.
            if(NOT PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_TARGETS_FILE)
                message(WARNING "PTSLC_CPP: Skipping ${EXPECTED_CONFIGURATION}, '${PTSLC_CPP_TARGET_FILE_TO_SEARCH}' was not found")
                continue()
            endif()

            # Alongside the targets file, we need to save the import prefix.
            set(PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_TARGETS_FILE_IMPORT_PREFIX "${${PTSLC_CPP_CONFIGURATION_ROOT_NAME}}")
            list(APPEND PTSLC_CPP_FOUND_CONFIGURATIONS_WITH_TARGETS_FILE "PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}")

            # Save the directory to include dependencies.
            get_filename_component(PTSLC_CPP_TARGETS_FILE_DIR "${PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_TARGETS_FILE}" DIRECTORY)
            list(APPEND PTSLC_CPP_DEPENDENCIES_TARGET_DIRECTORIES ${PTSLC_CPP_TARGETS_FILE_DIR})
        else()
            message(WARNING "PTSLC_CPP: Skipping ${EXPECTED_CONFIGURATION}, PTSLC_CPP_${EXPECTED_CONFIGURATION_UPPER}_ROOT is not set")
        endif()
    endforeach()
endif()

# Include targets from other configurations.

# Include dependencies target files.
foreach(d ${PTSLC_CPP_DEPENDENCIES_TARGET_DIRECTORIES})
    file(GLOB PTSLC_CPP_CURRENT_DEPENDENCIES_TARGET_FILES "${d}/PTSLC_CPPDependenciesTargets-*.cmake")
    foreach(f ${PTSLC_CPP_CURRENT_DEPENDENCIES_TARGET_FILES})
        message(STATUS "PTSLC_CPP: including dependencies: ${f}")
        include(${f})
    endforeach()
endforeach()

# Include the found targets files.
foreach(f ${PTSLC_CPP_FOUND_CONFIGURATIONS_WITH_TARGETS_FILE})
    message(STATUS "PTSLC_CPP: including targets: ${${f}_TARGETS_FILE}")
    # Should be okay. If not - maybe the targets file there requires more preparations from here. Like setting _IMPORT_PREFIX below.
    set(_IMPORT_PREFIX "${${f}_TARGETS_FILE_IMPORT_PREFIX}")
    include("${${f}_TARGETS_FILE}")
    unset(_IMPORT_PREFIX)
endforeach()

check_required_components("PTSLC_CPP")
