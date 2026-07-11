// Sprockets 4 precompile manifest (R10, POAM-017e follow-through).
//
// The JS bundle enumerates every file explicitly in application.js; the CSS bundle is
// built by dart-sass into app/assets/builds/application.css (which wins logical-path
// resolution over the .scss source). link_tree covers the view-referenced images
// (brand logos, favicons, placeholder). Fonts and theme sprites are served undigested
// from public/ since R9b. The former config.assets.precompile loose entries
// (jquery.nicescroll.js, animate.css, toastr.min.css, custom.css, green.png) were all
// verified unreferenced or relocated to public/ and are deliberately not linked.
//= link_tree ../images
//= link application.js
//= link application.css
