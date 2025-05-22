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

- [ ] #cu consider general alignment property or just make it a widget
- [ ] #cu disabled state for atoms
- [ ] #cu tooltips/dropdowns - general popups
- [ ] #cu focus behaviour
- [ ] #cu use icu or freebidi for bidi handling
- [ ] #cu #wgpu scrolling
    - [x] #cu overflow
    - [ ] #wgpu clip
    - [ ] #cu builder support
    - [ ] #cu event handling
- [ ] #cu truncate text with ellipses

- [ ] #wgpu texture/image rendering
    - [ ] consider wuffs for image loading (ghostty/pkg)
- [ ] #wgpu drop shadows
- [ ] #wgpu avoid reuploading texture every frame
    - profile first

- [ ] #sdl #wgpu Use wgpu renderer with sdl
    - or maybe we should keep the sdl backend

- [ ] #wl move wayland support into own mod

