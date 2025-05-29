# TODO

- [ ] #meta Migrate to github issue tracker for all of these
- [ ] #meta move each project under src into own project
    - the only issue I am facing with this is that some deps are used by both
      fe and cu. Can I create a shared module that then exposes these?
    
- [ ] #general intergrate google/breakpad for crash handling (ghostty/pkg)
- [ ] #general consider using google/highway for simd (ghostty/pkg)
- [ ] #general use simdutf for transcoding if I need it (ghostty/pkg)
- [ ] #general use utf8proc for normalization and other operations (ghostty/pkg)
- [ ] #general investigate using gtk for windowing and events
- [ ] #general pre-reserve mmaped memory for allocators
- [ ] #general hot reloading
    - maybe plugins?

- [x] #cu tooltips
- [x] #cu dropdowns/context menu 
- [x] #cu #wgpu scrolling
    - [x] #cu overflow
    - [x] #wgpu clip
    - [x] #cu builder support
    - [x] #cu event handling
- [x] #cu better font management system
- [ ] #cu consider general alignment property or just make it a widget
- [ ] #cu disabled state for atoms
- [ ] #cu focus behaviour
- [ ] #cu use icu or freebidi for bidi handling
- [ ] #cu truncate text with ellipses
- [ ] #cu smooth scroll

- [x] #wgpu avoid reuploading texture every frame
- [ ] #wgpu texture/image rendering
    - [ ] consider wuffs for image loading (ghostty/pkg)
- [ ] #wgpu drop shadows

- [ ] #sdl #wgpu Use wgpu renderer with sdl
    - or maybe we should keep the sdl backend

- [ ] #wl move wayland support into own module

- [ ] #cu text input
    - required inputs / actions
	- delete character back -> backspace
	- delete character forward -> delete
	- move caret left -> left
	- move caret right -> right
	- select character left -> shift+left
	- select character right -> shift+right
	- select all -> ctrl+a
	- move caret to start of line -> home
	- move caret to end of line -> end
	- show char palette -> ?
	- cut selection -> ctrl+x
	- copy selection -> ctrl+c
	- paste selection -> ctrl+v
    - mouse input
	- click -> figure out which char was clicked -> move caret there
	- drag -> create selection from start to end pos of drag
