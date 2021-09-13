set(tzcode_sources strftime.c)

add_library(tzcode STATIC ${tzcode_sources})

target_link_libraries(tzcode core)
