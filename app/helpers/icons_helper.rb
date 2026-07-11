# frozen_string_literal: true

# POAM-017e (R9b) — font-awesome-rails was removed (its stylesheet is now vendored plain
# CSS), but the gem also provided the `fa_icon` VIEW HELPER used at ~80 call sites
# (row actions, side menu, grids). This is a faithful reimplementation of the subset the
# app uses — same output as FontAwesome::Rails::IconHelper#fa_icon for these inputs:
#
#   fa_icon('pencil')                                  => <i class="fa fa-pencil"></i>
#   fa_icon('eye', 'aria-hidden': true)                => <i aria-hidden="true" class="fa fa-eye"></i>
#   fa_icon('trash', class: 'btn btn-danger')          => <i class="fa fa-trash btn btn-danger"></i>
#   fa_icon('camera 2x')                               => <i class="fa fa-camera fa-2x"></i>
#
# (The gem's `text:`/`right:` options and `fa_stacked_icon` are unused in this app and
# deliberately not carried over.)
module IconsHelper
  def fa_icon(names = 'flag', original_options = {})
    options = original_options.deep_dup
    classes = ['fa']
    classes.concat(names.to_s.split(' ').map { |n| "fa-#{n}" })
    classes.concat(Array(options.delete(:class)))
    content_tag(:i, nil, options.merge(class: classes))
  end
end
