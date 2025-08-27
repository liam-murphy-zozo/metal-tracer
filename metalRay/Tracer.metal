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

enum MaterialType {
    MATERIAL_NONE = -1,
    MATERIAL_DIFFUSE = 0,
    MATERIAL_LIGHT = 1,
    MATERIAL_DIFFUSE_SHINY = 2
};

struct HitObject {
    MaterialType material;
    float3 color;
    float3 hitNormal;
    float3 hitPosition;
    float hitDist;
    bool didHit;
};

HitObject getHit(Ray castingRay,
                 const constant SceneUniform& scene,
                 const constant Sphere* spheres,
                 const constant Plane* planes,
                 constant Disc* discs) {

    HitObject hitObj;
    hitObj.didHit = false;
    hitObj.hitDist = 1e19;

    for (int i = 0; i < scene.numSpheres; ++i) {
        float t;
        Ray normal;
        bool isHit = hitSphere(castingRay, spheres[i], t, normal);
        if (isHit && t < hitObj.hitDist ) {
            hitObj.hitDist = t;
            hitObj.material = MATERIAL_DIFFUSE;
            hitObj.color = spheres[i].color;
            hitObj.hitNormal = normal.direction;
            hitObj.hitPosition = normal.origin;
            hitObj.didHit = true;
        }
    }

    for (int i = 0; i < scene.numPlanes; ++i) {
        float t=1e20;
        Ray normal;

        bool isHit = hitPlane(castingRay, planes[i], t, normal);

        if (isHit && t < hitObj.hitDist ) {
            hitObj.hitDist = t;
            hitObj.material = MATERIAL_DIFFUSE;
            hitObj.hitDist = t;
            hitObj.color = planes[i].color;
            hitObj.hitNormal = normal.direction;
            hitObj.hitPosition = normal.origin;
            hitObj.didHit = true;
        }
    }

    for (int i = 0; i < scene.numDiscs; ++i) {
        float t=1e20;
        Ray normal;
        bool isHit = hitDisc(castingRay, discs[i], t, normal);
        if (isHit && t < hitObj.hitDist ) {
            hitObj.hitDist = t;
            hitObj.material = MATERIAL_LIGHT; // discs are lights for now..
            hitObj.hitDist = t;
            hitObj.color = spheres[i].color;
            hitObj.hitNormal = normal.direction;
            hitObj.hitPosition = normal.origin;
            hitObj.didHit = true;
        }
    }
    return hitObj;
}

float3 TraceRay(const thread Ray& castingRay,
                const constant SceneUniform& scene,
                const constant Sphere* spheres,
                const constant Plane* planes,
                const constant Disc* discs,
                uint seed,
                uint depthLimit) {

    float3 color(0);
    Ray ray = castingRay;
    for(uint i=0; i<depthLimit; ++i) {
        HitObject hitObj = getHit(ray, scene, spheres, planes, discs);
        if (!hitObj.didHit) return float3(0); // if we hit nothing, return black.

        if (hitObj.material == MATERIAL_LIGHT) {
            color*= float3(1); // solid light // THIS line aint right
        }

        if (hitObj.material == MATERIAL_DIFFUSE) {
            // construct new ray from hitPoint using randomness. (Diffuse BRDF)
            Ray bounceRay;
            if(i==0){
                color = hitObj.color;// * ;
            }else {
                //color *= hitObj.color * cosine ;
            }


        }
    }


    return color; //
}

kernel void raytrace(metal::texture2d<float, metal::access::write> output [[texture(0)]],  // Texture to render to.
    constant SceneUniform& scene [[buffer(0)]],
    constant Sphere* spheres [[buffer(1)]],
    constant Plane* planes [[buffer(2)]],
    constant Disc* discs [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

        Ray castingRay = constructCameraRay(gid, scene.camera, output.get_width(), output.get_height());

        uint seed = gid.x * gid.y * 4096;
        // to add sampling here...
        float3 color = TraceRay(castingRay,
                                scene,
                                spheres,
                                planes,
                                discs,
                                seed,
                                5);


        output.write(float4(color,0), gid);
}
