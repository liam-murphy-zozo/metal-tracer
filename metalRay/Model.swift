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

struct Plane {
    var position: SIMD3<Float>  // A point on the plane
    var normal: SIMD3<Float>
    var color: SIMD3<Float>
}

struct Disc {
    var position: SIMD3<Float>  // A point on the plane
    var normal: SIMD3<Float>
    var color: SIMD3<Float>
    var radius: Float
}

struct Camera {
    var position: SIMD3<Float>
    var orientation: matrix_float4x4
    var distanceToPlane: Float
    var height: Float
    var width: Float
    var padding: Float = 0
}

struct Ray {
    var origin: SIMD3<Float>
    var dir: SIMD3<Float>
}

struct Mesh { // not used for bindings but just for CPU side management of data.
    var vertices: [Float]
    var indices: [UInt32]
}

struct MeshMetaData {
    var numVertices: UInt32
    var numIndices: UInt32
    var vertexStride: UInt32
    var indexStride: UInt32
}



struct SceneUniform {
    var camera: Camera
    var numSpheres: Int32
    var numPlanes: Int32
    var numDiscs: Int32
    var numMeshes: Int32
    var numVertices: Int32
    var numIndices: Int32
    var frameIndex: UInt32
    var didChangeCamera: Bool
}

struct Scene { // Used for construction of scene, not to be transferred to GPU
    var sceneUniform: SceneUniform
    var spheres: [Sphere]
    var planes: [Plane]
    var discs: [Disc]
    var meshVertices: [Float]
    var meshIndices: [UInt32]
    var meshMetaData: [MeshMetaData]
}

