//
//  PostProcess.metal
//  metalRay
//
//  Created by Liam Murphy on 2025/08/29.
//
#include <metal_stdlib>
#include <simd/simd.h>



float4 gammaCorrect(float4 color, float gamma) {
    return metal::pow(color, float4(1.0 / gamma));
}

kernel void postProcess (
    metal::texture2d<float, metal::access::read> inputTexture [[texture(0)]],
    metal::texture2d<half, metal::access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        if (output.get_width() != inputTexture.get_width() || output.get_height() != inputTexture.get_height()) return;


        float4 prevSample = inputTexture.read(gid);
        float4 toneMapped = prevSample / (prevSample +1);
        float4 gamCorrect = gammaCorrect(toneMapped, 2.2);
        half4 newSample = half4(gamCorrect);//half4(gamCorrect.r, gamCorrect.g, gamCorrect.b, 1);

        output.write(newSample, gid);
 }
