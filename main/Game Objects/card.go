components {
  id: "card"
  component: "/main/Scripts/card.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"2_red\"\n"
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
