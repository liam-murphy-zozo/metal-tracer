//
//  Model.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/26.
//
import simd

struct Sphere {
    var position: SIMD3<Float> // X Y Z
    var radius: Float
    var color: SIMD3<Float> // RGB
}

struct Box {
    var position: SIMD3<Float> // Center
    var dimensions: SIMD3<Float> // Width, Height, Depth
    var color: SIMD3<Float> // RGB
}

struct Camera {
    var position: SIMD3<Float>
    var orientation: matrix_float4x4
    var distanceToPlane: Float
    var height: Float
    var width: Float
}

struct Ray {
    var origin: SIMD3<Float>
    var dir: SIMD3<Float>
}

struct SceneUniform {
    var camera: Camera
    var lightPosition: SIMD3<Float>
    var numSpheres: Int32
}

struct Scene { // Used for construction of scene, not to be transferred to GPU
    var sceneUniform: SceneUniform
    var spheres: [Sphere]
}
