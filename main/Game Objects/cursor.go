components {
  id: "cursor"
  component: "/main/Scripts/cursor.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"2_blue\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "size {\n"
  "  x: 10.0\n"
  "  y: 10.0\n"
  "}\n"
  "size_mode: SIZE_MODE_MANUAL\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/main/main.atlas\"\n"
  "}\n"
  ""
}
