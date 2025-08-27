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
    float3 color;
};

struct Box {
    float3 position;
    float3 dimensions;
    float3 color;
};

struct Plane {
    float3 position;
    float3 normal;
    float3 color;
};

struct Disc {
    float3 position;
    float3 normal;
    float3 color;
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
    int numPlanes;
    int numDiscs;
};

bool hitDisc(const thread Ray& ray, const constant Disc& p, thread float& t, thread Ray& normal) {
    float denom =  metal::dot(ray.direction, p.normal);
    if(denom > 1e-6) {
        float temp_t = metal::dot((p.position-ray.origin), p.normal) / denom;
        if (temp_t >=0) {
            float3 hitPoint = ray.origin + temp_t* ray.direction;
            if (metal::length_squared(hitPoint-p.position) < p.radius*p.radius) {
                normal = {hitPoint, p.normal};
                t = temp_t;
                return true;
            }

        }

    }


    return false;
}

bool hitPlane(const thread Ray& ray, const constant Plane& p, thread float& t, thread Ray& normal) {

    float denom =  metal::dot(ray.direction, p.normal);
    if(denom > 1e-6) {
        float temp_t = metal::dot((p.position-ray.origin), p.normal) / denom;
        if (temp_t >=0) {
            float3 hitPoint = ray.origin + temp_t* ray.direction;
            normal = {hitPoint, p.normal};
            t = temp_t;
            return true;
        }

    }


    return false;
}

bool hitSphere(const thread Ray& ray, const constant Sphere& s, thread float& t, thread Ray& normal) {
    float3 oc = ray.origin - s.position;
    float a = 1;// metal::dot(ray.direction, ray.direction); // We can eliminate this if we assume it is normalised.
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
        if (t<0) {
            // case where intersection behind ray?
            return false;
        }

        // calculate norm
        float3 hit_pos = ray.origin + t * ray.direction;

        normal = {hit_pos, metal::normalize(hit_pos - s.position)}; // could speed up by dividing by radius instead of using normalize?

        return true;
    }

    return false;  // This is a real hack we should have a bool instead to check
}

float lcg(thread uint &state) {
    state = 1664525u * state + 1013904223u;
    return metal::fract((float)state / 4294967296.0);
}

Ray constructCameraRay(uint2 gid, constant Camera& camera, const float width, const float height) {
    float widthStride = camera.width / width;
    float heightStride = camera.height / height;

    Ray castingRay;
    castingRay.origin = camera.position;
    float4 forward = camera.orientation[2] * camera.distToPlane;
    float4 left = camera.orientation[0] * (gid.x*widthStride - ( widthStride * width/2));
    float4 up = camera.orientation[1]   * (gid.y*heightStride - (heightStride * height/2));
    float4 newDir = forward + left + up;

    castingRay.direction = {newDir.x , newDir.y, newDir.z};
    castingRay.direction = metal::normalize(castingRay.direction);

    return castingRay;
}

float3 TraceRay(Ray castingRay, const constant SceneUniform& scene, const constant Sphere* spheres, const constant Plane* planes, const constant Disc* discs) {
    float3 color(0);
    float closest_t = 1e19;
    for (int i = 0; i < scene.numSpheres; ++i) {
        float t;
        Ray normal;
        bool isHit = hitSphere(castingRay, spheres[i], t, normal);
        if (isHit && t < closest_t ) {
            closest_t = t;

            color = spheres[i].color * metal::dot(normal.direction, metal::normalize(scene.lightPosition-normal.origin));
        }
    }

     for (int i = 0; i < scene.numPlanes; ++i) {
         float t=1e20;
         Ray normal;

         bool isHit = hitPlane(castingRay, planes[i], t, normal);

         if (isHit && t < closest_t ) {
             closest_t = t;

             color = planes[i].color * -1* metal::dot(normal.direction, metal::normalize(scene.lightPosition-normal.origin));
         }
     }

    for (int i = 0; i < scene.numDiscs; ++i) {
         float t=1e20;
         Ray normal;
         bool isHit = hitDisc(castingRay, discs[i], t, normal);
         if (isHit && t < closest_t ) {
             closest_t = t;

             color = discs[i].color * -1* metal::dot(normal.direction, metal::normalize(scene.lightPosition-normal.origin));
         }
     }

    return color;
}

kernel void raytrace(metal::texture2d<float, metal::access::write> output [[texture(0)]],  // Texture to render to.
    constant SceneUniform& scene [[buffer(0)]],
    constant Sphere* spheres [[buffer(1)]],
    constant Plane* planes [[buffer(2)]],
    constant Disc* discs [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

        Ray castingRay = constructCameraRay(gid, scene.camera, output.get_width(), output.get_height());

        float3 color = TraceRay(castingRay,
                                scene,
                                spheres,
                                planes,
                                discs);


        output.write(float4(color,0), gid);
}
