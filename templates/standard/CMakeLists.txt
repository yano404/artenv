cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
project(artemis-working-dir-template) # your project name

# ROOT 6 installation
list(APPEND CMAKE_PREFIX_PATH $ENV{ROOTSYS})

# Default installation dir
set(CMAKE_INSTALL_PREFIX ${CMAKE_SOURCE_DIR}/install/ CACHE PATH "install dir" FORCE)

# Build options
#option(BUILD_IDAQ2ROOT "Build and install Isobe DAQ data to ROOT converter" ON)

# path definitions
find_package(artemis HINTS ${TARTSYS} REQUIRED)
#if(NOT ${ARTEMIS_BUILD_GET})
#    message(SEND_ERROR "artemis is not built with GETDecoder which is required by src-oedo. Rebuild artemis with BUILD_GET=ON")
#endif()

#---Locate the ROOT package and defines a number of variables (e.g. ROOT_INCLUDE_DIRS)
find_package(ROOT REQUIRED COMPONENTS RIO Net Physics Minuit Minuit2 Geom Gui Genetic)
find_package(yaml-cpp REQUIRED HINTS ${ARTEMIS_YAML_CPP_LIB_DIR}/../)

#-fPIC
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

#---Define useful ROOT functions and macros (e.g. ROOT_GENERATE_DICTIONARY)
include(${ROOT_USE_FILE})

link_directories(${ARTEMIS_GET_LIB_DIR})

add_subdirectory(src)
