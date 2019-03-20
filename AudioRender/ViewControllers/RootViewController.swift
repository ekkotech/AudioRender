//
//  ViewController.swift
//  AudioRender
//
//  Created by Andrew Coad on 08/02/2019.
//  Copyright © 2019 ___EKKO-TECH LTD___. All rights reserved.
//

import UIKit
import MediaPlayer
import Accelerate

//
// Action control
let kFileReadProfilerEnable             = false
let kPlayFile                           = false
let kMultiReaderEnable                  = true

//
// General constants
//
enum ChannelMode:AVAudioChannelCount {
    case mono = 1
    case stereo = 2
}

//
// File reader profile control
//
let kPcmBuffSize:AVAudioFrameCount      = 1024 * 512
let kReaderNumThreads                   = 6

class RootViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    //
    // MARK: - Outlets
    //
    @IBOutlet weak var libraryButton: UIButton!
    @IBOutlet weak var filesButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet var containerView: UIView!
    
    //
    // MARK: - Private properties
    //
    private var playFile:AVAudioFile = AVAudioFile()
    private let audioSession:AVAudioSession = AVAudioSession.sharedInstance()
    private var processingFormat:AVAudioFormat? = nil
    private var systemSampleRate:Double? = nil
    private var channelMode:ChannelMode = .stereo
    private var player:AVAudioPlayerNode = AVAudioPlayerNode()
    private var engine:AVAudioEngine = AVAudioEngine()
    //
    private let maxDisplayWidth = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
    private let pointAdjustment:CGFloat = Int(UIScreen.main.scale) % 2 == 0 ? 0.0 : 0.5
    //
    private var fileListViewController:UITableViewController? = nil
    private let fileResources:[(displayName: String, fileName: String, fileExt: String)] =
        [("Aaya Lolo 48kHz 192kbps mp3", "Aaya Lolo-48-MP3-192", "mp3"),
         ("Aaya Lolo 48kHz, wav", "Aaya Lolo-48-WAV", "wav"),
         ("Aaya Lolo 48kHz 192kbps AAC", "Aaya Lolo-48-AAC-192", "m4a"),
         ("Able Mable 44.1kHz 128kbps wav", "Able Mable (LP Version)", "wav")]
    
    //
    // Sample buffers
    //
    private var sliderSamples:SampleBuffer? = nil
    private var scrollerSamples:SampleBuffer? = nil
    
    //
    // File read profiling variables
    //
    private struct ProfileBlock {
        var buffer:AVAudioPCMBuffer
        var framesRead:AVAudioFrameCount
        var startTime:TimeInterval
        var endTime:TimeInterval
    }
    private var profile:[ProfileBlock] = []
    private let fileReadGroup:DispatchGroup = DispatchGroup.init()
    private let readerQueue:DispatchQueue = DispatchQueue.init(label: "readerQ", qos: .userInitiated, attributes: .concurrent)
    private let reportQueue:DispatchQueue = DispatchQueue.init(label: "reportQ", qos: .unspecified)
    private let bufferSize = AVAudioFrameCount(kPcmBuffSize)
    
    //
    // File ripping support
    //
    private var baseSampleBuffer:UnsafeMutablePointer<Float>? = nil
    private let downsampleQueue:DispatchQueue = DispatchQueue.init(label: "dsQ", qos: .userInitiated)
    private let dsConcQueue:DispatchQueue = DispatchQueue.init(label: "dsConQ", qos: .userInitiated, attributes: .concurrent)
    private let builderQueue:DispatchQueue = DispatchQueue.init(label: "bldQ", qos: .userInitiated)
    private let ripFileGroup:DispatchGroup = DispatchGroup.init()
    
    //
    // MARK: - Initialisation
    //
    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        setupAudioSession()
        setupAudioEngine()
    }
    
    //
    // MARK: - Orientation change handling
    //
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    //
    // MARK: - Geometry management
    //
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    //
    // MARK: - IBAction handlers
    //
    @IBAction func handleLibraryButtonTouchUp(_ sender: Any) {
        let mediaPicker:MPMediaPickerController = MPMediaPickerController(mediaTypes: .anyAudio)
        mediaPicker.delegate = self
        mediaPicker.allowsPickingMultipleItems = false
        mediaPicker.prompt = "Select song"
        present(mediaPicker, animated: true, completion: {
            Logger.debug("Media picker presented")
        })
    }
    
    @IBAction func handleFileButtonTouchUp(_ sender: Any) {
        
        let storyboard = UIStoryboard.init(name: "Main", bundle: nil)
        fileListViewController = storyboard.instantiateViewController(withIdentifier: "fileListViewController") as? UITableViewController
        if let flvc = fileListViewController {
            flvc.tableView.delegate = self
            flvc.tableView.dataSource = self
            flvc.modalPresentationStyle = .overCurrentContext
            present(flvc, animated: true, completion: nil)
        }
        
    }
    
    @IBAction func handlePreviousButtonTouchUp(_ sender: Any) {
        
        stopPlayer()
        playFile.framePosition = 0
        player.scheduleSegment(playFile, startingFrame: 0, frameCount: AVAudioFrameCount(playFile.length), at: nil, completionHandler: {
            self.playButton.isEnabled = false
        })
        playButton.isSelected = false
        playButton.isEnabled = true
        previousButton.isEnabled = true
    }
    
    @IBAction func handlePlayButtonTouchUp(_ sender: Any) {
        
        playButton.isSelected = !playButton.isSelected
        
        if playButton.isSelected {
            if !engine.isRunning { startEngine() }
            startPlayer()
        }
        else {
            pausePlayer()
        }
    }
    
    //
    // MARK: - Initialisation Support Functions
    //
    private func setupControls() {
        #if targetEnvironment(simulator)
        libraryButton.isEnabled = false
        filesButton.isEnabled = true
        #else
        libraryButton.isEnabled = true
        filesButton.isEnabled = false
        #endif
        
        previousButton.isEnabled = false
        playButton.setImage(UIImage(named: "Stop"), for: .selected)
        playButton.setImage(UIImage(named: "Play"), for: .normal)
        playButton.isEnabled = false
    }
    
    private func setupAudioSession() {
        
        do {
            try AVAudioSessionPatch.setSession(audioSession, category: .playback)
            systemSampleRate = audioSession.sampleRate
            processingFormat = AVAudioFormat(standardFormatWithSampleRate: audioSession.sampleRate, channels: channelMode.rawValue)
        }
        catch {
            assertionFailure("Error setting up audio session")
            print("Error setting up audio session")
        }
    }
    
    private func setupAudioEngine() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        attachNodesToEngine()
        makeEngineConnections()
        engine.prepare()
    }
    
    private func attachNodesToEngine() {
        // Attach nodes, connect tree
        engine.attach(player)
    }
    
    private func makeEngineConnections() {
        // connect the player to the main mixer node
        engine.connect(player, to: engine.mainMixerNode, format: processingFormat)
    }
    
    //
    // MARK: - Utility Functions
    //
    private func startEngine() {
        do {
            try engine.start()
        }
        catch {
            print("Error starting engine")
        }
    }
    
    private func stopEngine() {
        engine.stop()
    }
    
    private func pauseEngine() {
        engine.pause()
    }
    
    private func startPlayer() {
        player.play()
    }
    
    private func pausePlayer() {
        player.pause()
    }
    
    private func stopPlayer() {
        player.stop()
    }
    
    private func activateSession() {
        do {
            try audioSession.setActive(true)
        }
        catch {
            print("Error activating audio session")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false)
        }
        catch {
            print("Error deactivating audio session")
        }
    }
    
    func onSampleBuffer(sBuff:SampleBuffer) {
        
    }
    
}

//
// MARK: - Media Picker Delegate
//
extension RootViewController: MPMediaPickerControllerDelegate {
    
    func mediaPicker(_ mediaPicker: MPMediaPickerController,
                     didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        
        dismiss(animated: true, completion: nil)
        if mediaItemCollection.count < 1 {
            return
        }
        
        let mediaItem:MPMediaItem = mediaItemCollection.items[0]
        if let assetURL:URL = mediaItem.value(forProperty: MPMediaItemPropertyAssetURL) as? URL {
            
            if player.isPlaying { stopPlayer() }
            assetSelected(assetURL: assetURL)
            
//            if kPlayFile {
                do {
                    playFile = try AVAudioFile(forReading: assetURL)
                    
                    player.scheduleSegment(playFile, startingFrame: 0, frameCount: AVAudioFrameCount(playFile.length), at: nil, completionHandler: {
                        self.playButton.isEnabled = false
                        self.previousButton.isEnabled = false
                    })
                    previousButton.isEnabled = true
                    playButton.isSelected = false
                    playButton.isEnabled = true
                }
                catch {
                    print("Error opening file: \(assetURL)")
                }
//            }
        }
    }
    
    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
        Logger.debug("Media picked cancelled")
        dismiss(animated: true, completion: nil)
    }
    
    private func assetSelected(assetURL:URL) {
        guard let pf = processingFormat, let cvc = children.first as? WaveformViewContainer else { return }
        
        // Stop player etc.
        cvc.setAsset(assetURL: assetURL, pFormat:pf)
        
    }
    
}

//
// MARK: - File Read Profiler
//
extension RootViewController {
    
    private func profileReadFile(asset: URL, threads: Int) {
        let readerBlock:(URL, Array<ProfileBlock>, Int, @escaping ()->())->() = { (asset, buffers, thisThread, callback) in
            // thisThread is zero-indexed
            guard buffers.count > 0, buffers.count > thisThread else {
                assertionFailure("Invalid input values")
                return }
            
            var sourceFile:AVAudioFile
            var startFrame:AVAudioFramePosition
            var endFrame:AVAudioFramePosition
            var startTime:TimeInterval
            var endTime:TimeInterval
            var framesRead:AVAudioFrameCount = 0
            
            do {
                try sourceFile = AVAudioFile(forReading: asset)
                startFrame = AVAudioFramePosition(thisThread) * (sourceFile.length / AVAudioFramePosition(buffers.count))
                sourceFile.framePosition = startFrame
                endFrame = startFrame + (sourceFile.length / AVAudioFramePosition(buffers.count))
                endFrame = endFrame > sourceFile.length ? sourceFile.length : endFrame
                startTime = CACurrentMediaTime()
                
                while sourceFile.framePosition < endFrame {
                    do {
                        let framesToRead:AVAudioFrameCount = AVAudioFrameCount(endFrame - sourceFile.framePosition) > kPcmBuffSize ? kPcmBuffSize : AVAudioFrameCount(endFrame - sourceFile.framePosition)
                        try sourceFile.read(into: buffers[thisThread].buffer, frameCount: framesToRead)
                        framesRead += AVAudioFrameCount(buffers[thisThread].buffer.frameLength)
                    }
                    catch { assertionFailure("Unable to read into PCM buffer") }
                }
                endTime = CACurrentMediaTime()
                self.reportQueue.async {
                    self.profile[thisThread].startTime = startTime
                    self.profile[thisThread].endTime = endTime
                    self.profile[thisThread].framesRead = framesRead
                    callback()
                }
            }
            catch {
                assertionFailure("Unable to open file for reading")
            }
        }
        
        guard let pf = processingFormat else {
            assertionFailure("Invalid processing format (nil)")
            return }
        
        //
        // Set up profile array
        //
        for _ in 0..<threads {
            if let pbuff = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: bufferSize) {
                profile.append(ProfileBlock(buffer: pbuff, framesRead: 0, startTime: 0, endTime: 0))
            }
            else { assertionFailure("Error allocating PCM buffer") }
        }
        
        //
        // Kick off file reads
        //
        for idx in 0..<threads {
            self.fileReadGroup.enter()
            readerQueue.async {
                readerBlock(asset, self.profile, idx, {
                    self.fileReadGroup.leave()
                })
            }
        }
        fileReadGroup.notify(queue: DispatchQueue.main, execute: {
            //
            // Print timing
            //
            let starts = self.profile.map( { $0.startTime } )
            let ends = self.profile.map( { $0.endTime } )
            let frames = self.profile.map( { $0.framesRead }).reduce(0, +)
            for idx in 0..<self.profile.count {
                print("Thread: \(idx) Start: \(starts[idx]) End: \(ends[idx]) Elapsed: \(ends[idx] -  starts[idx]) Frames Read: \(self.profile[idx].framesRead)")
            }
            if let last = ends.max(), let first = starts.min() {
                print("Total elapsed: \(last - first) Total Frames: \(frames)")
            }
        })
    }
}

//
// MARK: - Table View Delegate
//
extension RootViewController {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let section = indexPath.section
        let row = indexPath.row
        
        if section == 0 {
            if let url = Bundle.main.url(forResource: fileResources[row].fileName,
                                         withExtension: fileResources[row].fileExt) {
                assetSelected(assetURL: url)
                dismiss(animated: true, completion: nil)
            }
        }
        else if section == 1 {
            dismiss(animated: true, completion: nil)
        }
    }
    
}

//
// MARK: - Table View Data Source
//
extension RootViewController {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return section == 0 ? fileResources.count : 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let section = indexPath.section
        let row = indexPath.row
        
        if section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "fileDetail", for: indexPath)
            cell.backgroundColor = UIColor.clear
            cell.textLabel?.text = fileResources[row].displayName
            cell.textLabel?.textColor = UIColor.darkGray
            return cell
        }
        else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cancelCell", for: indexPath)
            cell.textLabel?.text = "Cancel"
            cell.textLabel?.textColor = UIColor.white
            cell.textLabel?.textAlignment = .center
            cell.backgroundColor = UIColor.init(rgb: 0x2D91EC, alpha: 1.0)
            return cell
        }
    }
    
}
