// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#include <metal_stdlib>
using namespace metal;

struct PhotoPreviewVertex {
  float2 position;
  float2 textureCoordinate;
};

struct PhotoPreviewRasterData {
  float4 position [[position]];
  float2 textureCoordinate;
};

vertex PhotoPreviewRasterData photoPreviewVertex(
  uint vertexID [[vertex_id]],
  constant PhotoPreviewVertex *vertices [[buffer(0)]]) {
  PhotoPreviewRasterData output;
  output.position = float4(vertices[vertexID].position, 0.0, 1.0);
  output.textureCoordinate = vertices[vertexID].textureCoordinate;
  return output;
}

fragment half4 photoPreviewFragment(
  PhotoPreviewRasterData input [[stage_in]],
  texture2d<half> image [[texture(0)]]) {
  constexpr sampler imageSampler(filter::linear, address::clamp_to_edge);
  return image.sample(imageSampler, input.textureCoordinate);
}
