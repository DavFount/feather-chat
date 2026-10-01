export function resolve(base, override) {
  return Object.fromEntries(Object.entries(base).map(([key, value]) => [key,
    override && typeof override[key] === 'string' && override[key] !== '' ? override[key] : value]))
}
export function render(dictionary, key, variables = {}) {
  return (dictionary[key] || key).replace(/\{([\w]+)\}/g,
    (token, name) => variables[name] == null ? token : String(variables[name]))
}
