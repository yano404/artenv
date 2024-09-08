
# Artemis Working Directory Template

You should change these variables to suite your analysis environment.

- project name in `CMakeLists`
```cmake
project(artemis-working-dir-template)
```
- `LIB_NAME` in `src/CMakeLists.txt`
```cmake
set(LIB_NAME template) # your project name
```
- loaded library name in `artemislogon.C`
```cpp
gSystem->Load("libtemplate"); // LIB_NAME in src/CMakeLists.txt
```

