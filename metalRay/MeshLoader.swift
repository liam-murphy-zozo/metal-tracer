//
//  MeshLoader.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/30.
//
import Foundation

func loadMesh(filename: String) -> Mesh? {

    let url = URL(fileURLWithPath: filename)
    let fileExtension = url.pathExtension
    let fileNameWithoutExtension = url.deletingPathExtension().lastPathComponent

    let localURL = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: fileExtension)!
    var vertices: [Float] = []
    var indices: [UInt32] = []
    var normals: [Float] = []

    if fileExtension == "obj" {

        // obj loader
        do {
            let contents = try String(contentsOf: localURL, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                let splits = line.split(separator: " ")
                if splits.first == "v" {
                    if splits.count != 4 {
                        print("Warning: Vertex line \(i) does not contain 4 elements")
                        continue
                    }
                    vertices.append(Float(splits[1])!)
                    vertices.append(Float(splits[2])!)
                    vertices.append(Float(splits[3])!)
                } else if splits.first == "f" {
                    if splits.count != 4 {
                        print("Warning: Face line \(i) does not contain 4 elements")
                        continue
                    }
                    for j in 1...3 {
                        let facePart = splits[j].split(separator: "/", omittingEmptySubsequences: false)
                        indices.append(UInt32(facePart[0])!)
                        if facePart.count > 1 { // there were slashes...
                            if facePart[2] != "" {
                                normals.append(Float(facePart[2])!)

                            }
                        }
                    }
                }


            }
        } catch {
            print("Error reading file \(localURL): \(error)")
            return nil
        }

        if vertices.count % 3 != 0 {
            print("Error: Incorrect vertex data, must be a multiple of 3")
            return nil
        }

        if indices.count % 3 != 0 {
            print("Error: Incorrect vertex data, must be a multiple of 3")
            return nil
        }

    }
    print("Succesfully Loaded: \(localURL)")
    return Mesh(vertices: vertices, indices: indices)
}
