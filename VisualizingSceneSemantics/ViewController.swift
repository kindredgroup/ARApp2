/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import RealityKit
import ARKit
import Combine

var collisionSubscribing:Cancellable? // Keeping the reference is required to listen for events


class ViewController: UIViewController, ARSessionDelegate, URLSessionDownloadDelegate {
    @IBOutlet var arView: ARView!
    @IBOutlet weak var hideMeshButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var planeDetectionButton: UIButton!
    var downloadedModel: Entity = Entity()
    
    var selected: Int = 0
    
    let coachingOverlay = ARCoachingOverlayView()
    
    // Cache for 3D text geometries representing the classification values.
    var modelsForClassification: [ARMeshClassification: ModelEntity] = [:]

    /// - Tag: ViewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView.session.delegate = self
        
        setupCoachingOverlay()

        arView.environment.sceneUnderstanding.options = []
        
        // Turn on occlusion from the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Turn on physics for the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.physics)

        // Display a debug visualization of the mesh.
        arView.debugOptions.insert(.showSceneUnderstanding)
        
        // For performance, disable render options that are not required for this app.
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
        
        // Manually configure what kind of AR session to run since
        // ARView on its own does not turn on mesh classification.
        arView.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification

        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapRecognizer)
        
        let tapRecognizer2 = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        arView.addGestureRecognizer(tapRecognizer2)
        
        collisionSubscribing = arView.scene.subscribe(to: CollisionEvents.Began.self) { event in
            print("collision ! \(event.entityA.name) with \(event.entityB.name)")
            print(event.entityA.name)
            let entityA = event.entityA as? ModelEntity
            let entityB = event.entityB as? ModelEntity
             // Collision entity
            if (event.entityA.name=="ball" && event.entityB.name=="Ground Plane"){
                print("BOOOM!")
            }
        }
        

        let url = URL(string:"https://github.com/kindredgroup/ARApp2/raw/master/VisualizingSceneSemantics/Fruitmachine.reality")!
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        let downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(with: url)
        downloadTask.resume()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @objc
    func handleLongPress(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)
        print("LONG PRESS")
    }
    
    /// Places virtual-text of the classification at the touch-location's real-world intersection with a mesh.
    /// Note - because classification of the tapped-mesh is retrieved asynchronously, we visualize the intersection
    /// point immediately to give instant visual feedback of the tap.
    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        // 1. Perform a ray cast against the mesh.
        // Note: Ray-cast option ".estimatedPlane" with alignment ".any" also takes the mesh into account.
        let tapLocation = sender.location(in: arView)
        if let result = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any).first {
            // ...
            // 2. Visualize the intersection point of the ray with the real-world surface.
            let resultAnchor = AnchorEntity(world: result.worldTransform)
            resultAnchor.addChild(sphere(radius: 0, color: .red))
            if (selected == 0) {
                resultAnchor.addChild(createModel())
            }
            if (selected == 1) {
                resultAnchor.addChild(createModel1())
            }
            if (selected == 2) {
                resultAnchor.addChild(createModel2())
            }
            arView.scene.addAnchor(resultAnchor, removeAfter: 60)

            /*
            // 3. Try to get a classification near the tap location.
            //    Classifications are available per face (in the geometric sense, not human faces).
            nearbyFaceWithClassification(to: result.worldTransform.position) { (centerOfFace, classification) in
                // ...
                DispatchQueue.main.async {
                    // 4. Compute a position for the text which is near the result location, but offset 10 cm
                    // towards the camera (along the ray) to minimize unintentional occlusions of the text by the mesh.
                    let rayDirection = normalize(result.worldTransform.position - self.arView.cameraTransform.translation)
                    let textPositionInWorldCoordinates = result.worldTransform.position - (rayDirection * 0.1)
                    
                    // 5. Create a 3D text to visualize the classification result.
                    let textEntity = self.model(for: classification)

                    // 6. Scale the text depending on the distance, such that it always appears with
                    //    the same size on screen.
                    let raycastDistance = distance(result.worldTransform.position, self.arView.cameraTransform.translation)
                    textEntity.scale = .one * raycastDistance

                    // 7. Place the text, facing the camera.
                    var resultWithCameraOrientation = self.arView.cameraTransform
                    resultWithCameraOrientation.translation = textPositionInWorldCoordinates
                    let textAnchor = AnchorEntity(world: resultWithCameraOrientation.matrix)
                    textAnchor.addChild(textEntity)
                    self.arView.scene.addAnchor(textAnchor, removeAfter: 3)

                    // 8. Visualize the center of the face (if any was found) for three seconds.
                    //    It is possible that this is nil, e.g. if there was no face close enough to the tap location.
                    if let centerOfFace = centerOfFace {
                        let faceAnchor = AnchorEntity(world: centerOfFace)
                        faceAnchor.addChild(self.sphere(radius: 0.01, color: classification.color))
                        self.arView.scene.addAnchor(faceAnchor, removeAfter: 3)
                    }
                }
            }
            */
        }
    }
    
    @IBAction func resetButtonPressed(_ sender: Any) {
        if let configuration = arView.session.configuration {
            arView.session.run(configuration, options: .resetSceneReconstruction)
            loadModels()
            selected += 1
            if (selected>2) {
                selected = 0
            }
        }
    }
    
    @IBAction func toggleMeshButtonPressed(_ button: UIButton) {
        let isShowingMesh = arView.debugOptions.contains(.showSceneUnderstanding)
        if isShowingMesh {
            arView.debugOptions.remove(.showSceneUnderstanding)
            button.setTitle("Show Mesh", for: [])
            
        } else {
            arView.debugOptions.insert(.showSceneUnderstanding)
            button.setTitle("Hide Mesh", for: [])
        }
    }
    
    /// - Tag: TogglePlaneDetection
    @IBAction func togglePlaneDetectionButtonPressed(_ button: UIButton) {
        guard let configuration = arView.session.configuration as? ARWorldTrackingConfiguration else {
            return
        }
        if configuration.planeDetection == [] {
            configuration.planeDetection = [.horizontal, .vertical]
            button.setTitle("Stop Plane Detection", for: [])
        } else {
            configuration.planeDetection = []
            button.setTitle("Start Plane Detection", for: [])
        }
        arView.session.run(configuration)
    }
    
    func nearbyFaceWithClassification(to location: SIMD3<Float>, completionBlock: @escaping (SIMD3<Float>?, ARMeshClassification) -> Void) {
        guard let frame = arView.session.currentFrame else {
            completionBlock(nil, .none)
            return
        }
    
        var meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor })
        
        // Sort the mesh anchors by distance to the given location and filter out
        // any anchors that are too far away (4 meters is a safe upper limit).
        let cutoffDistance: Float = 4.0
        meshAnchors.removeAll { distance($0.transform.position, location) > cutoffDistance }
        meshAnchors.sort { distance($0.transform.position, location) < distance($1.transform.position, location) }

        // Perform the search asynchronously in order not to stall rendering.
        DispatchQueue.global().async {
            for anchor in meshAnchors {
                for index in 0..<anchor.geometry.faces.count {
                    // Get the center of the face so that we can compare it to the given location.
                    let geometricCenterOfFace = anchor.geometry.centerOf(faceWithIndex: index)
                    
                    // Convert the face's center to world coordinates.
                    var centerLocalTransform = matrix_identity_float4x4
                    centerLocalTransform.columns.3 = SIMD4<Float>(geometricCenterOfFace.0, geometricCenterOfFace.1, geometricCenterOfFace.2, 1)
                    let centerWorldPosition = (anchor.transform * centerLocalTransform).position
                     
                    // We're interested in a classification that is sufficiently close to the given location––within 5 cm.
                    let distanceToFace = distance(centerWorldPosition, location)
                    if distanceToFace <= 0.05 {
                        // Get the semantic classification of the face and finish the search.
                        let classification: ARMeshClassification = anchor.geometry.classificationOf(faceWithIndex: index)
                        completionBlock(centerWorldPosition, classification)
                        return
                    }
                }
            }
            
            // Let the completion block know that no result was found.
            completionBlock(nil, .none)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetButtonPressed(self)
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
        
    func model(for classification: ARMeshClassification) -> ModelEntity {
        // Return cached model if available
        if let model = modelsForClassification[classification] {
            model.transform = .identity
            return model.clone(recursive: true)
        }
        
        // Generate 3D text for the classification
        let lineHeight: CGFloat = 0.05
        let font = MeshResource.Font.systemFont(ofSize: lineHeight)
        let textMesh = MeshResource.generateText(classification.description, extrusionDepth: Float(lineHeight * 0.1), font: font)
        let textMaterial = SimpleMaterial(color: classification.color, isMetallic: true)
        let model = ModelEntity(mesh: textMesh, materials: [textMaterial])
        // Move text geometry to the left so that its local origin is in the center
        model.position.x -= model.visualBounds(relativeTo: nil).extents.x / 2
        // Add model to cache
        modelsForClassification[classification] = model
        return model
    }
    
    func sphere(radius: Float, color: UIColor) -> Entity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: color, isMetallic: false)])
        sphere.position.y = radius
        // Move sphere up by half its diameter so that it does not intersect with the mesh
        return sphere
    }
    
    func createModel() -> Entity {
        var e:Entity = Entity()
        let url = getDocumentsDirectory().appendingPathComponent("ExperienceDownload.reality")
        print("MODEL path = \(url)")
        do {
            let model = try Entity.load(contentsOf: url)
            print("MODEL loaded.")
            e = model
        } catch {
            print(error)
            print("MODEL Fail loading entity.")
        }

        e.name = "object1"
        return e
    }
    
    func createModel1() -> Entity {
        var e:Entity = Entity()
        if let x = try? Entity.load(named: "Experience1.reality") {
            e = x
        }
        e.name = "object2"
        return e
    }
    
    func createModel2() -> Entity {
        var e:Entity = Entity()
        if let x = try? Entity.load(named: "Experience2.reality") {
            e = x
        }
        e.name = "object3"
        return e
    }
    
    func addGlobe(radius: Float, color: UIColor, x:Float, y:Float, z:Float) {
        let anchorEntity = AnchorEntity(world: [x,y,z])
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = SimpleMaterial(color: color, isMetallic: true)
        let shape = ShapeResource.generateSphere(radius: radius)
        let spherePhysicsMaterial = PhysicsMaterialResource.generate(friction: 0.055, restitution: 0.85)
        let sphere = ModelEntity(mesh: mesh, materials: [material], collisionShape:shape, mass: 0.5)
        let kinematics: PhysicsBodyComponent = .init(massProperties: .default, material: spherePhysicsMaterial, mode: .dynamic)
        sphere.components.set(kinematics)
        sphere.name="ball"
        sphere.setParent(anchorEntity)
        let m = createModel1()
        //m.setParent(anchorEntity)
        arView.scene.addAnchor(anchorEntity)
        sphere.transform.translation.x = x
        sphere.transform.translation.y = y
        sphere.transform.translation.z = z
        print("Added sphere")
    }
    
    func loadModels() {
        // ** TODO get and process JSON
        let anchorEntity = AnchorEntity(world: [0,0,0])
        addGlobe(radius:0.2, color: .blue, x:-0.3,y:0.2,z:-2)
        addGlobe(radius:0.1, color: .green, x:0,y:0.2,z:-2)
        addGlobe(radius:0.1, color: .yellow, x:0.3,y:0.2,z:-2)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        print("Download finished: \(location)")
        // Create The Filename
        let fileURL = getDocumentsDirectory().appendingPathComponent("ExperienceDownload.reality")

        // Copy It To The Documents Directory
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // delete file
                do {
                    try FileManager.default.removeItem(atPath: fileURL.path)
                    print("MODEL deleted file")
                } catch {
                    print("MODEL Could not delete file, probably read-only filesystem")
                }
            }
            try FileManager.default.copyItem(at: location, to: fileURL)

            print("MODEL Successfuly Saved File \(fileURL)")

            // Load The Model
            

        } catch {
            print("MODEL Error Saving: \(error)")
        }
    }

}

/// Returns The Documents Directory
///
/// - Returns: URL
func getDocumentsDirectory() -> URL {

let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = paths[0]
return documentsDirectory

}
