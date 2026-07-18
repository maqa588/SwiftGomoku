# Compiling & Integrating Rapfi Engine for iOS

Because iOS sandboxing forbids launching external executable subprocesses (`Foundation.Process` is not available on iOS), we cannot use the standard macOS approach of piping stdin/stdout to the Rapfi binary. 

To run Rapfi on iOS, you have two primary implementation paths: **Option A (Native C++ Static Library)** and **Option B (WebAssembly inside WKWebView)**. Below is the step-by-step guide for both approaches.

---

## Option A: Native C++ Static Library & Obj-C++ Bridge

This approach compiles Rapfi directly to ARM64 machine code for iOS devices and links it statically into your Swift project.

### 1. Exposing C-Compatible APIs in Rapfi
We need to bypass the standard blocking command loop (`Command::gomocupLoop()` inside `main.cpp`) which waits on `stdin` reads. Instead, we write a simple bridging API (`extern "C"`) to send command strings directly to the engine and receive callbacks.

Create a new file `bridge.cpp` inside the `Rapfi` source directory:

```cpp
#include "command/command.h"
#include <string>

// Callback function type to send engine output back to Swift
typedef void (*EngineOutputCallback)(const char* output);
static EngineOutputCallback g_callback = nullptr;

// Custom printer function replacing stdout prints
void ios_engine_print(const std::string& line) {
    if (g_callback) {
        g_callback(line.c_str());
    }
}

extern "C" {
    // 1. Initialize engine configuration
    void rapfi_init(EngineOutputCallback callback) {
        g_callback = callback;
        // Override standard output printer helper with our callback redirect
        // Expose settings & config loader
        Command::loadConfig();
    }

    // 2. Pass standard Piskvork command directly to command parser
    void rapfi_send_command(const char* command) {
        std::string cmd(command);
        // Direct feed to the Piskvork protocol command handler inside Rapfi
        // Example: Command::handleSingleCommand(cmd);
    }
}
```

### 2. Compiling the C++ Code for iOS Architectures
Using `cmake`, you can compile the library for both iOS Devices (ARM64) and iOS Simulators (x86_64 and ARM64).

Run these commands inside the `rapfi` directory:

```bash
# Build for iOS Device (ARM64)
mkdir -p Rapfi/build/ios-device && cd Rapfi/build/ios-device
cmake ../.. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_NEON=ON \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config Release

# Build for iOS Simulator (ARM64 + x86_64)
cd ../..
mkdir -p Rapfi/build/ios-simulator && cd Rapfi/build/ios-simulator
cmake ../.. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_NEON=ON \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config Release
```

### 3. Packaging as an XCFramework
Combine the compiled static library files into an `XCFramework` so they can be cleanly imported into Xcode:

```bash
xcodebuild -create-xcframework \
  -library Rapfi/build/ios-device/librapfi.a \
  -headers Rapfi/include \
  -library Rapfi/build/ios-simulator/librapfi.a \
  -headers Rapfi/include \
  -output Rapfi/build/Rapfi.xcframework
```

### 4. Linking and Invoking in SwiftGomoku
1. Drag `Rapfi.xcframework` into your SwiftGomoku project under **Frameworks, Libraries, and Embedded Content**.
2. Create a Bridging Header (`SwiftGomoku-Bridging-Header.h`) containing:
   ```c
   void rapfi_init(void (*callback)(const char* output));
   void rapfi_send_command(const char* command);
   ```
3. Implement a custom manager in Swift:
   ```swift
   class NativeRapfiEngine {
       init() {
           rapfi_init { cStringOutput in
               guard let cString = cStringOutput else { return }
               let outputLine = String(cString: cString)
               // Forward outputLine to SwiftGomoku's engine parser
               NotificationCenter.default.post(name: .receivedEngineOutput, object: outputLine)
           }
       }

       func send(command: String) {
           rapfi_send_command(command)
       }
   }
   ```

---

## Option B: WebAssembly (WASM) & WKWebView (Recommended)

This is the easiest and most modern integration pattern. Apple allows JIT compilation inside `WKWebView`, so running WebAssembly code in JavaScript executes at almost identical speeds to native C++ compilation while bypassing static compilation/linking headaches.

### 1. Compiling to WebAssembly using Emscripten
Set up the [Emscripten SDK](https://emscripten.org/) and compile Rapfi as a WebAssembly target. Emscripten compiles C++ into JS and WASM files:

```bash
mkdir -p Rapfi/build/wasm && cd Rapfi/build/wasm
emcmake cmake ../.. \
  -DCMAKE_BUILD_TYPE=Release \
  -DNO_COMMAND_MODULES=ON \
  -DUSE_WASM_SIMD=ON \
  -DNO_MULTI_THREADING=OFF

emmake cmake --build .
```
This produces `rapfi.js` and `rapfi.wasm`.

### 2. Loading the Engine in a Headless WKWebView
Create a local HTML page `index.html` inside your Swift project:

```html
<!DOCTYPE html>
<html>
<head>
    <script src="rapfi.js"></script>
    <script>
        // Setup local callbacks from WASM to iOS app
        var engineInstance = null;
        Module.onRuntimeInitialized = function() {
            // WASM engine is ready
            window.webkit.messageHandlers.iosBridge.postMessage({ type: "status", data: "ready" });
        };
        
        // Listen to engine standard output print callbacks
        Module.print = function(text) {
            window.webkit.messageHandlers.iosBridge.postMessage({ type: "output", data: text });
        };

        function sendCommand(cmd) {
            // Expose a JS method to call the WASM input functions directly
            Module.ccall('handle_piskvork_cmd', 'void', ['string'], [cmd]);
        }
    </script>
</head>
<body></body>
</html>
```

### 3. Bridging WKWebView to Swift
Initialize a hidden `WKWebView` in your Swift engine layer:

```swift
import WebKit

class WebAssemblyEngine: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "iosBridge")
        config.userContentController = controller
        
        // Load on a headless background web view
        webView = WKWebView(frame: .zero, configuration: config)
        
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // Capture prints sent from WASM javascript context
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String,
              let data = dict["data"] as? String else { return }
        
        if type == "output" {
            // Forward data to your standard SwiftGomoku parser (e.g. handle received move coordinate)
            print("Received from WASM: \(data)")
        }
    }

    func send(command: String) {
        webView.evaluateJavaScript("sendCommand('\(command)')", completionHandler: nil)
    }
}
```

This dynamic WKWebView WASM approach is highly recommended for iOS since it avoids cross-compilation target mismatches and runs in an isolated context safely.
