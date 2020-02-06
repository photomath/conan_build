cmake_minimum_required(VERSION 3.15.5)

# in order to be able to detect AppleClang, as opposed to Clang, we need to set this policy
cmake_policy( SET CMP0025 NEW )

enable_language( C CXX  )





option( PM_SKIP_CONAN_INSTALL "Prevent CMake from calling conan install" OFF )

if( NOT COMMAND remote_include )
    macro( remote_include file_name url fallback_url )
        if( NOT EXISTS "${CMAKE_BINARY_DIR}/${file_name}" )
            set( download_succeeded FALSE )
            foreach( current_url ${url} ${fallback_url} )
                set( download_attempt 1 )
                set( sleep_seconds 1 )
                while( NOT ${download_succeeded} AND ${download_attempt} LESS_EQUAL 3 )
                    message( STATUS "Downloading pm_conan_build.cmake from ${current_url}. Attempt #${download_attempt}" )
                    file(
                        DOWNLOAD
                            "${current_url}"
                            "${CMAKE_BINARY_DIR}/${file_name}"
                        SHOW_PROGRESS
                        TIMEOUT
                            2  # 2 seconds timeout
                        STATUS
                            download_status
                    )
                    list( GET download_status 0 error_status      )
                    list( GET download_status 1 error_description )
                    if ( error_status EQUAL 0 )
                        set( download_succeeded TRUE )
                    else()
                        message( STATUS "Download failed due to error: [code: ${error_status}] ${error_description}" )
                        math( EXPR download_attempt "${download_attempt} + 1" OUTPUT_FORMAT DECIMAL )
                        math( EXPR sleep_seconds "${sleep_seconds} + 1" OUTPUT_FORMAT DECIMAL )
                        message( STATUS "Sleep ${sleep_seconds} seconds" )
                        execute_process( COMMAND "${CMAKE_COMMAND}" -E sleep "${sleep_seconds}" )
                    endif()
                endwhile()
                if ( ${download_succeeded} )
                    # break the foreach loop
                    break()
                else()
                    # remove empty file
                    file( REMOVE "${CMAKE_BINARY_DIR}/${file_name}" )
                endif()
            endforeach()
            if ( NOT ${download_succeeded} )
                # remove empty file
                file( REMOVE "${CMAKE_BINARY_DIR}/${file_name}" )
                message( FATAL_ERROR "Failed to download ${file_name}, even after ${download_attempt} retrials. Please check your Internet connection!" )
            endif()
        endif()

        include( ${CMAKE_BINARY_DIR}/${file_name} )
    endmacro()
endif()

# in conan local cache or user has already performed conan install command
if( CONAN_EXPORTED OR PM_SKIP_CONAN_INSTALL )
    # standard conan installation, deps will be defined in conanfile.py
    # and not necessary to call conan again, conan is already running
    if( EXISTS ${CMAKE_CURRENT_BINARY_DIR}/conanbuildinfo_multi.cmake )
        include( ${CMAKE_CURRENT_BINARY_DIR}/conanbuildinfo_multi.cmake )
    else()
        include( ${CMAKE_CURRENT_BINARY_DIR}/conanbuildinfo.cmake )
    endif()
    set( basic_setup_params TARGETS )
    if( IOS )
        list( APPEND basic_setup_params NO_OUTPUT_DIRS )
    endif()
    conan_basic_setup( ${basic_setup_params} )
else() # in user space and user has not performed conan install command


    # if not using IDE generator and build type is not set, use Release build type
    if ( NOT CONAN_CMAKE_MULTI AND NOT CMAKE_BUILD_TYPE )
        set( CMAKE_BUILD_TYPE Release )
    endif()

    remote_include( "conan.cmake" "http://raw.githubusercontent.com/microblink/cmake-conan/v0.15.1/conan.cmake" "http://files.microblink.com/conan.cmake" )

    set( conan_cmake_run_params BASIC_SETUP CMAKE_TARGETS )
    if( IOS )
        list( APPEND conan_cmake_run_params NO_OUTPUT_DIRS )
    endif()
    
    # detect profile
    set( HAVE_PROFILE OFF )
    if( IOS )
        list( APPEND conan_cmake_run_params PROFILE ios-clang)
        set( HAVE_PROFILE ON )
    elseif( CMAKE_SYSTEM_NAME STREQUAL "Linux" )
        list( APPEND conan_cmake_run_params PROFILE linux-clang)
        set( HAVE_PROFILE ON )
    elseif( CMAKE_SYSTEM_NAME STREQUAL "Darwin" )
        list( APPEND conan_cmake_run_params PROFILE mac-clang)
        set( HAVE_PROFILE ON )
    endif()

    if( PM_CONAN_SETUP_PARAMS )
        list( APPEND conan_cmake_run_params ${PM_CONAN_SETUP_PARAMS} )
    endif()

    if ( HAVE_PROFILE )
        # use automatically detected build type when using profile
        list( APPEND conan_cmake_run_params PROFILE_AUTO build_type )
    endif()

    # other cases should be auto-detected by conan.cmake

    # Make sure to use conanfile.py to define dependencies, to stay consistent
    if ( CONANFILE_LOCATION )
        set( CONANFILE ${CONANFILE_LOCATION} )
    else()
        if ( EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/conanfile.py )
            set( CONANFILE conanfile.py )
        elseif( EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/conanfile.txt )
            set( CONANFILE conanfile.txt )
        endif()
    endif()
    if ( NOT CONANFILE )
        message( FATAL_ERROR "Cannot find neither conanfile.py nor conanfile.txt in current source directory. You can also use CONANFILE_LOCATION to specify path to either conanfile.py or conanfile.txt and override automatic detection." )
    endif()

    conan_cmake_run( CONANFILE ${CONANFILE} ${conan_cmake_run_params} )

    if ( CONAN_CMAKE_MULTI )
        # workaround for https://github.com/conan-io/conan/issues/1498
        # in our case, it's irrelevant which version is added - we need access to cmake files
        set(CMAKE_PREFIX_PATH ${CONAN_CMAKE_MODULE_PATH_RELEASE} ${CMAKE_PREFIX_PATH})
        set(CMAKE_MODULE_PATH ${CONAN_CMAKE_MODULE_PATH_RELEASE} ${CMAKE_MODULE_PATH})
    endif()
endif()

# if this include fails, then you have forgot to add
# build_requires = "CMakeBuild/<latest-version>@microblink/stable"
# to your conanfile.py
include( common )