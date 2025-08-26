//
//  Tracer.metal
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

#include <metal_stdlib>
#include <simd/simd.h>

struct Sphere {
    float3 position;
    float radius;
};

struct Camera {
    float3 position;
    matrix_float4x4 orientation;
    float distToPlane;
    float height;
    float width;
};

struct Ray {
    float3 origin;
    float3 direction;
};

struct SceneUniform {
    Camera camera;
    float3 lightPosition;
    int numSpheres;
};

Ray hitSphere(thread Ray& ray, constant Sphere& s, thread float& t) {
    float3 oc = ray.origin - s.position;
    float a = metal::dot(ray.direction, ray.direction); // We can eliminate this if we assume it is normalised.
    float b = 2.0 * metal::dot(oc, ray.direction);
    float c = metal::dot(oc, oc) - s.radius * s.radius;

    float discriminant = b * b - 4.0 * a * c;
    t = 1e20;
    if (discriminant >= 0.0) {
        if (discriminant == 0) {
            t = -b / (2.0 * a);
        } else {
            float t_0 = (-b - metal::sqrt(discriminant)) / (2.0 * a);
            float t_1 = (-b + metal::sqrt(discriminant)) / (2.0 * a);
            t = t_0 < t_1 ? t_0 : t_1;
        }
        if (t < 0) {
            t=1e20;
        }
        // calculate norm
        float3 hit_pos = ray.origin + t * ray.direction;
        float3 normal = metal::normalize(hit_pos - s.position); // could speed up by dividing by radius instead of using normalize?
        return Ray {hit_pos, normal };
    }

    return Ray { float3(0), float3(0)};  // This is a real hack we should have a bool instead to check
}

kernel void raytrace(
    metal::texture2d<float, metal::access::write> output [[texture(0)]],  // Texture to render to.
                     constant SceneUniform& scene [[buffer(0)]],
                     constant Sphere* spheres [[buffer(1)]],
                     uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return; // check if this

        Camera camera = scene.camera;
        float widthStride = camera.width / output.get_width();
        float heightStride = camera.height / output.get_height();

        Ray castingRay;
        castingRay.origin = camera.position;
        float4 forward = camera.orientation[2] * camera.distToPlane;
        float4 left = camera.orientation[0] * (gid.x*widthStride - ( widthStride * output.get_width()/2));
        float4 up = camera.orientation[1]   * (gid.y*heightStride - (heightStride * output.get_height()/2));
        float4 newDir = forward + left + up;

        castingRay.direction = {newDir.x , newDir.y, newDir.z};
        castingRay.direction = metal::normalize(castingRay.direction);

        float3 color = float3(0.0);
        float closest_t = 1e19;
        for (int i = 0; i < scene.numSpheres; ++i) {
            float t;
            Ray normal = hitSphere(castingRay, spheres[i], t);
            if (t < closest_t ) {
                closest_t = t;
                float3 lightSource {5, 10, 0};
                color = float3(1,0,0) * metal::dot(normal.direction, metal::normalize(normal.origin-lightSource));
            }
        }


        output.write(float4(color,0), gid);
}
