//
//  Model.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/26.
//
import simd

struct Sphere {
    var position: SIMD3<Float>
    var radius: Float
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
    var spheres: [Sphere]
    var numSpheres: Int
}
