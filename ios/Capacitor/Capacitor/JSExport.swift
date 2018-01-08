/**
 * PluginExport handles defining JS APIs that map to registered
 * plugins and are responsible for proxying calls to our bridge.
 */
public class JSExport {
  static let CATCHALL_OPTIONS_PARAM = "_options"
  static let CALLBACK_PARAM = "_callback"
  
  public static func exportAvocadoJS(userContentController: WKUserContentController) throws {
    guard let jsUrl = Bundle.main.url(forResource: "public/native-bridge", withExtension: "js") else {
      print("ERROR: Required native-bridge.js file in Avocado not found. Bridge will not function!")
      throw BridgeError.errorExportingCoreJS
    }
    
    do {

      let data = try String(contentsOf: jsUrl, encoding: .utf8)
      let userScript = WKUserScript(source: data, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      userContentController.addUserScript(userScript)
    } catch {
      print("ERROR: Unable to read required native-bridge.js file from Avocado framework. Bridge will not function!")
      throw BridgeError.errorExportingCoreJS
    }
  }
  
  /**
   * Export the JS required to implement the given plugin.
   */
  public static func exportJS(webView: WKWebView, pluginClassName: String, pluginType: CAPPlugin.Type) {
    var lines = [String]()
    
    lines.append("""
      (function(w) {
      w.Avocado = w.Avocado || {};
      w.Avocado.Plugins = w.Avocado.Plugins || {};
      var a = w.Avocado; var p = a.Plugins;
      var t = p['\(pluginClassName)'] = {};
      t.addListener = function(eventName, callback) {
        return w.Avocado.addListener('\(pluginClassName)', eventName, callback);
      }
      t.removeListener = function(eventName, callback) {
        return w.Avocado.removeListener('\(pluginClassName)', eventName, callback);
      }
      """)
    let bridgeType = pluginType as! CAPBridgedPlugin.Type
    let methods = bridgeType.pluginMethods() as! [CAPPluginMethod]
    for method in methods {
      lines.append(generateMethod(pluginClassName: pluginClassName, method: method))
    }
    
    lines.append("""
    })(window);
    """)
    
    let js = lines.joined(separator: "\n")
    
    webView.evaluateJavaScript(js) { (result, error) in
      if error != nil {
        print("ERROR EXPORTTING PLUGIN JS", js)
      } else if result != nil {
        print(result!)
      }
    }
  }
  
  private static func generateMethod(pluginClassName: String, method: CAPPluginMethod) -> String {
    let methodName = method.name!
    let returnType = method.returnType!
    var paramList = [String]()
    
    // add the catch-all
    // options argument which takes a full object and converts each
    // key/value pair into an option for plugin call.
    paramList.append(CATCHALL_OPTIONS_PARAM)
    
    // Automatically add the _callback param if returning data through a callback
    if returnType == CAPPluginReturnCallback {
      paramList.append(CALLBACK_PARAM)
    }
    
    // Create a param string of the form "param1, param2, param3"
    let paramString = paramList.joined(separator: ", ")
    
    // Generate the argument object that will be sent on each call
    let argObjectString = CATCHALL_OPTIONS_PARAM
    
    var lines = [String]()
    
    // Create the function declaration
    lines.append("t['\(method.name!)'] = function(\(paramString)) {")
    
    // Create the call to Avocado...
    if returnType == CAPPluginReturnNone {
      // ...using none
      lines.append("""
        return w.Avocado.nativeCallback('\(pluginClassName)', '\(methodName)', \(argObjectString));
        """)
    } else if returnType == CAPPluginReturnPromise {
      
      // ...using a promise
      lines.append("""
        return w.Avocado.nativePromise('\(pluginClassName)', '\(methodName)', \(argObjectString));
      """)
    } else if returnType == CAPPluginReturnCallback {
      // ...using a callback
      lines.append("""
        return w.Avocado.nativeCallback('\(pluginClassName)', '\(methodName)', \(argObjectString), \(CALLBACK_PARAM));
        """)
    } else {
      print("Error: plugin method return type \(returnType) is not supported!")
    }
    
    // Close the function
    lines.append("}")
    return lines.joined(separator: "\n")
  }
}