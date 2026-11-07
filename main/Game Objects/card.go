components {
  id: "card"
  component: "/main/Scripts/card.script"
}
embedded_components {
  id: "shadow"
  type: "sprite"
  data: "default_animation: \"back\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size {\n"
  "  x: 90.0\n"
  "  y: 150.0\n"
  "}\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/main/main.atlas\"\n"
  "}\n"
  position {
    x: 6.0
    y: -8.0
    z: -0.001
  }
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"back\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size {\n"
  "  x: 90.0\n"
  "  y: 150.0\n"
  "}\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/main/main.atlas\"\n"
  "}\n"
  ""
  position {
    x: 1.0
    y: -1.0
  }
}
embedded_components {
  id: "portrait"
  type: "sprite"
  data: "default_animation: \"back\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size {\n"
  "  x: 90.0\n"
  "  y: 150.0\n"
  "}\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/main/main.atlas\"\n"
  "}\n"
  ""
  position {
    x: 1.0
    y: -1.0
    z: 0.0001
  }
}
embedded_components {
  id: "outline"
  type: "sprite"
  data: "default_animation: \"card_outline\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size { x: 90.0 y: 150.0 }\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures { sampler: \"texture_sampler\" texture: \"/gui/theme.atlas\" }\n"
  position { x: 1.0 y: -1.0 z: 0.0002 }
}
embedded_components {
  id: "hint"
  type: "sprite"
  data: "default_animation: \"card_hint\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size { x: 98.0 y: 158.0 }\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures { sampler: \"texture_sampler\" texture: \"/gui/theme.atlas\" }\n"
  position { x: 1.0 y: -1.0 z: 0.0003 }
}
