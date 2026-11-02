///|
#cfg(target="js")
extern "js" fn host_request() -> String? =
  #|() => typeof globalThis.__moonSurfaceInput === 'string' ? globalThis.__moonSurfaceInput : null

///|
#cfg(not(target="js"))
fn host_request() -> String? {
  None
}

///|
#cfg(target="js")
extern "js" fn host_response(text : String) -> Bool =
  #|(text) => {
  #|  if (typeof globalThis.__moonSurfaceInput !== 'string') return false;
  #|  globalThis.__moonSurfaceOutput = text;
  #|  return true;
  #|}

///|
#cfg(not(target="js"))
fn host_response(_text : String) -> Bool {
  false
}

///|
fn main {
  let input = match host_request() {
    Some(text) => text
    None => {
      let args = @env.args()
      if args.is_empty() {
        "{}"
      } else {
        args[args.length() - 1]
      }
    }
  }
  let output = @exchange.execute_json(input)
  if !host_response(output) {
    println(output)
  }
}
