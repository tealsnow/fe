_local state_ -> `createSignal`
_complex state_ -> `createStore`
_share state_ -> drill props
_share state "globaly" (persist)_ -> `createContext` w/wo `createStore`
_persist state (less powerful context)_ -> `createRoot` w/ signal or store

**never pass setters through props**
