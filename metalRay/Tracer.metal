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

struct MeshMetaData {
    uint numVertices;
    uint numIndices;
    uint vertexStride;
    uint indexStride;
};

struct Camera {
    float3 position; //16 (float3 is 16 in metal)
    matrix_float4x4 orientation; // 64 bytes
    float distToPlane; // 4
    float height; // 4
    float width; // 4
    float padding1; // 4
};

struct Ray {
    float3 origin;
    float3 direction;
};

struct SceneUniform {
    Camera camera;
    int numSpheres;
    int numPlanes;
    int numDiscs;
    int numMeshes;
    int numVertices;
    int numIndices;
    uint frameIndex;
    bool didChangeCamera;
};

bool hitDisc(const thread Ray& ray, const constant Disc& p, thread float& t, thread Ray& normal) {
    float denom =  metal::dot(ray.direction, p.normal);
    if(denom < 0) {
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
    if(denom < 0 ) {
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

bool hitSphere(const thread Ray& ray, const constant Sphere& s, thread float& t, thread Ray& hitAndNormal) {
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

        hitAndNormal = {hit_pos, metal::normalize(hit_pos - s.position)}; // could speed up by dividing by radius instead of using normalize?

        return true;
    }

    return false;  // This is a real hack we should have a bool instead to check
}

float lcg(thread uint &state) {
    state = 1664525u * state + 1013904223u;
    return metal::fract((float)state / 4294967296.0);
}

uint hash2D(uint x, uint y) {
    uint seed = x * 374761393u + y * 668265263u; // large primes
    seed = (seed ^ (seed >> 13)) * 1274126177u;
    return seed ^ (seed >> 16);
}

Ray constructCameraRay(uint2 gid, constant Camera& camera, const float width, const float height, uint seed) {
    float widthStride = camera.width / width;
    float heightStride = camera.height / height;

    Ray castingRay;
    castingRay.origin = camera.position;
    float offset = lcg(seed) -0.5; // more circular distribution if used for x and y right?
    float4 forward = camera.orientation[2] * camera.distToPlane;
    float4 left = camera.orientation[0] * (gid.x*widthStride - ( widthStride * width/2) + offset*widthStride);
    float4 up = camera.orientation[1]   * (gid.y*heightStride - (heightStride * height/2) + offset*heightStride);
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
            hitObj.color = discs[i].color;
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

    float3 radiance = float3(0);
    float3 throughput = float3(1.0);
    Ray ray = castingRay;
    for(uint i=0; i<depthLimit; ++i) {
        HitObject hitObj = getHit(ray, scene, spheres, planes, discs);
        if (!hitObj.didHit) {
            break;
        }

        if (hitObj.material == MATERIAL_LIGHT) {
            radiance+= throughput * hitObj.color; // should be bright light?
            break;
           // return color; // No need to bounce if we hit light? // solid light // THIS line aint right
        }

        if (hitObj.material == MATERIAL_DIFFUSE) {
            // construct new ray from hitPoint using randomness. (Diffuse BRDF)
            Ray bounceRay;

            float theta = 2 * M_PI_F * lcg(seed);

            float z = 2* lcg(seed) - 1;
            float xyproj = metal::sqrt(1 - (z * z));
            bounceRay.direction.x = xyproj * metal::cos(theta);
            bounceRay.direction.y = xyproj * metal::sin(theta);
            bounceRay.direction.z = z;
            bounceRay.origin = hitObj.hitPosition+ 0.0001 * hitObj.hitNormal;// should this be offset by normal rather than ray direction..?

            if(metal::dot(bounceRay.direction, hitObj.hitNormal) < 0) {
                bounceRay.direction *= -1;
            }
//            bounceRay.direction = metal::normalize(bounceRay.direction); // not needed
            ray = bounceRay;

            throughput *= hitObj.color * metal::dot(hitObj.hitNormal, bounceRay.direction);
        }
    }


    return radiance; //
}


    float4 mix(float4 old, float4 newSample, float weight) {
        return (1-weight) * old + newSample * weight;
    }

kernel void raytrace(
    metal::texture2d<float, metal::access::read> inputTexture [[texture(0)]],
    metal::texture2d<float, metal::access::write> output [[texture(1)]],  // Texture to render to.
    constant SceneUniform& scene [[buffer(0)]],
    constant Sphere* spheres [[buffer(1)]],
    constant Plane* planes [[buffer(2)]],
    constant Disc* discs [[buffer(3)]],
    constant MeshMetaData* meshes [[buffer(4)]],
    constant float* vertexBuffer [[buffer(5)]],
    constant uint* indiceBuffer [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    uint seed = hash2D(gid.x+ scene.frameIndex * 7919u, gid.y);
    float4 prevSample = inputTexture.read(gid);
    float4 runningSample(0);
    for(int s=0; s<10; s++) {
        Ray castingRay = constructCameraRay(gid, scene.camera, output.get_width(), output.get_height(), seed);
        float3 newSample = TraceRay(castingRay,
                                    scene,
                                    spheres,
                                    planes,
                                    discs,
                                    seed,
                                    5);
        runningSample+= float4(newSample, 1);
    }

    if(scene.didChangeCamera) {
        output.write(runningSample, gid);
        return;
    }

    float4 updatedSample = prevSample + runningSample;
    output.write(updatedSample, gid);
}
