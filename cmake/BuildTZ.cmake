macro(libtzcode_build)
    set(LIBTZ_LIBRARIES tzcode)

    add_subdirectory(${PROJECT_SOURCE_DIR}/third_party/tzcode)
endmacro()
