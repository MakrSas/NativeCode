import Foundation
import Dispatch
import Darwin

#if canImport(Python)
import Python
#endif

struct NCPythonResult {
    let succeeded: Bool
    let output: String
    let runtimeAvailable: Bool
}

enum NCPythonRuntime {
    private static let executionQueue = DispatchQueue(label: "com.makrsas.NativeCode.python", qos: .userInitiated)

    static var isAvailable: Bool {
        #if canImport(Python)
        return true
        #else
        return false
        #endif
    }

    static func execute(source: String, fileName: String) async -> NCPythonResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<NCPythonResult, Never>) in
            executionQueue.async {
                continuation.resume(returning: executeSynchronously(source: source, fileName: fileName))
            }
        }
    }

    private static func executeSynchronously(source: String, fileName: String) -> NCPythonResult {
        #if canImport(Python)
        guard let pythonHome = pythonHomeURL() else {
            return NCPythonResult(
                succeeded: false,
                output: "Python runtime is not bundled in this build.",
                runtimeAvailable: false
            )
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeCodePython", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root.appendingPathComponent("main.py")
        let outputURL = root.appendingPathComponent("output.txt")
        let statusURL = root.appendingPathComponent("status.txt")

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        } catch {
            return NCPythonResult(succeeded: false, output: error.localizedDescription, runtimeAvailable: true)
        }

        setenv("PYTHONHOME", pythonHome.path, 1)
        setenv("PYTHONPATH", pythonHome.appendingPathComponent("lib").path, 1)
        setenv("PYTHONNOUSERSITE", "1", 1)

        if !runtimeInitialized {
            Py_Initialize()
            runtimeInitialized = true
        }

        let launcher = """
        import sys
        import traceback

        _nc_output = open(\(pythonLiteral(outputURL.path)), "w", encoding="utf-8")
        sys.stdout = _nc_output
        sys.stderr = _nc_output
        try:
            with open(\(pythonLiteral(sourceURL.path)), "r", encoding="utf-8") as _nc_source_file:
                _nc_source = _nc_source_file.read()
            _nc_globals = {"__name__": "__main__", "__file__": \(pythonLiteral(fileName))}
            exec(compile(_nc_source, \(pythonLiteral(fileName)), "exec"), _nc_globals, _nc_globals)
            with open(\(pythonLiteral(statusURL.path)), "w", encoding="utf-8") as _nc_status:
                _nc_status.write("success")
        except BaseException:
            traceback.print_exc()
            with open(\(pythonLiteral(statusURL.path)), "w", encoding="utf-8") as _nc_status:
                _nc_status.write("failure")
        finally:
            _nc_output.flush()
            _nc_output.close()
        """

        let pythonStatus = launcher.withCString { command in
            PyRun_SimpleString(command)
        }
        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let status = (try? String(contentsOf: statusURL, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: root)

        if pythonStatus != 0 && output.isEmpty {
            return NCPythonResult(
                succeeded: false,
                output: "Python interpreter failed to start (status \(pythonStatus)).",
                runtimeAvailable: true
            )
        }

        return NCPythonResult(
            succeeded: status == "success",
            output: output.isEmpty ? (status == "success" ? "Finished with no output." : "Python execution failed.") : output,
            runtimeAvailable: true
        )
        #else
        return NCPythonResult(
            succeeded: false,
            output: "This build does not contain the embedded Python runtime.",
            runtimeAvailable: false
        )
        #endif
    }

    #if canImport(Python)
    private static var runtimeInitialized = false

    private static func pythonHomeURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("Python.framework", isDirectory: true),
            Bundle.main.url(forResource: "Python", withExtension: "framework"),
            Bundle.main.url(forResource: "python", withExtension: nil)
        ]

        return candidates.compactMap { $0 }.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("lib").path)
        }
    }

    private static func pythonLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
    #endif
}
