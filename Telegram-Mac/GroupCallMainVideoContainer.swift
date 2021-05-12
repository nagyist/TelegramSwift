//
//  GroupCallMainVideoContainer.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 06.04.2021.
//  Copyright © 2021 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox


struct DominantVideo : Equatable {
    let peerId: PeerId
    let endpointId: String
    let mode: VideoSourceMacMode
    let temporary: Bool
    init(_ peerId: PeerId, _ endpointId: String, _ mode: VideoSourceMacMode, _ temporary: Bool) {
        self.peerId = peerId
        self.endpointId = endpointId
        self.mode = mode
        self.temporary = temporary
    }
}

final class GroupCallMainVideoContainerView: Control {
    private let call: PresentationGroupCall
    
    private(set) var currentVideoView: GroupVideoView?
    private(set) var currentPeer: DominantVideo?
    
    let shadowView: ShadowView = ShadowView()
    
    private var validLayout: CGSize?
    
    private let nameView: TextView = TextView()
    private var statusView: TextView = TextView()
    let gravityButton = ImageButton()

    var currentResizeMode: CALayerContentsGravity = .resizeAspect {
        didSet {
            self.currentVideoView?.setVideoContentMode(currentResizeMode, animated: true)
        }
    }
    
    private let speakingView: View = View()
    
    private let audioLevelDisposable = MetaDisposable()
    
    init(call: PresentationGroupCall, resizeMode: CALayerContentsGravity) {
        self.call = call
        self.currentResizeMode = resizeMode
        super.init()
        
        
        speakingView.layer?.cornerRadius = 10
        speakingView.layer?.borderWidth = 2
        speakingView.layer?.borderColor = GroupCallTheme.speakActiveColor.cgColor
        
        
        self.backgroundColor =  GroupCallTheme.membersColor
        addSubview(shadowView)
        
        shadowView.shadowBackground = NSColor.black.withAlphaComponent(0.3)
        shadowView.direction = .vertical(true)
        
        self.layer?.cornerRadius = 10
        
        //addSubview(gravityButton)
        
        gravityButton.sizeToFit()
        gravityButton.scaleOnClick = true
        gravityButton.autohighlight = false
        addSubview(nameView)
        addSubview(statusView)
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        
        addSubview(speakingView)
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    func updateMode(controlsMode: GroupCallView.ControlsMode, controlsState: GroupCallControlsView.Mode, animated: Bool) {
        shadowView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        gravityButton.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        
        nameView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        statusView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)

        gravityButton.set(image:  controlsState == .fullscreen ?  GroupCallTheme.videoZoomOut : GroupCallTheme.videoZoomIn, for: .Normal)
        gravityButton.sizeToFit()
    }
    
    private var participant: PeerGroupCallData?
    
    
    
    func updatePeer(peer: DominantVideo?, participant: PeerGroupCallData?, transition: ContainedViewLayoutTransition, animated: Bool, controlsMode: GroupCallView.ControlsMode, arguments: GroupCallUIArguments?) {
        
        
        transition.updateAlpha(view: speakingView, alpha: participant?.isSpeaking == true ? 1 : 0)
                
        transition.updateAlpha(view: shadowView, alpha: controlsMode == .normal ? 1 : 0)
        transition.updateAlpha(view: gravityButton, alpha: controlsMode == .normal ? 1 : 0)
        transition.updateAlpha(view: nameView, alpha: controlsMode == .normal ? 1 : 0)
        transition.updateAlpha(view: statusView, alpha: controlsMode == .normal ? 1 : 0)
        if participant != self.participant, let participant = participant, let peer = peer {
            self.participant = participant
            let text: String
            if participant.peer.id == participant.accountPeerId {
                text = L10n.voiceChatStatusYou
            } else {
                text = participant.peer.displayTitle
            }
            let nameLayout = TextViewLayout(.initialize(string: text, color: NSColor.white.withAlphaComponent(0.8), font: .medium(.short)), maximumNumberOfLines: 1)
            nameLayout.measure(width: frame.width - 20)
            self.nameView.update(nameLayout)
                        
            
            let status = participant.videoStatus(peer.mode)
            
            if self.statusView.layout?.attributedString.string != status {
                let statusLayout = TextViewLayout(.initialize(string: status, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.short)), maximumNumberOfLines: 1)
                
                statusLayout.measure(width: frame.width - nameView.frame.width - 30)
                
                let statusView = TextView()
                statusView.update(statusLayout)
                statusView.userInteractionEnabled = false
                statusView.isSelectable = false
                statusView.layer?.opacity = controlsMode == .normal ? 1 : 0
                
                statusView.frame = CGRect(origin: NSMakePoint(nameView.frame.width + 20, frame.height - statusView.frame.height - 10), size: self.statusView.frame.size)
                self.addSubview(statusView)
                
                let previous = self.statusView
                self.statusView = statusView
                if animated, controlsMode == .normal {
                    previous.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak previous] _ in
                        previous?.removeFromSuperview()
                    })
                    statusView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    statusView.layer?.animatePosition(from: statusView.frame.origin - NSMakePoint(10, 0), to: statusView.frame.origin)

                    previous.layer?.animatePosition(from: previous.frame.origin, to: previous.frame.origin + NSMakePoint(10, 0))
                } else {
                    previous.removeFromSuperview()
                }
            }
            
                        
            self.updateLayout(size: self.frame.size, transition: transition)
        }

        
        if self.currentPeer == peer {
            return
        }
        
        if let peer = peer, let arguments = arguments, let audioLevel = arguments.audioLevel(peer.peerId) {
            audioLevelDisposable.set(audioLevel.start(next: { [weak self] value in
                if let value = value {
                    self?.speakingView.layer?.opacity = Float(min(value, 6) / 6)
                } else {
                    self?.speakingView.layer?.opacity = 0
                }
            }))
        } else {
            audioLevelDisposable.set(nil)
        }
        
        self.currentPeer = peer
        if let peer = peer {
           
            
            guard let videoView = arguments?.takeVideo(peer.peerId, peer.mode) as? GroupVideoView else {
                return
            }
            videoView.videoView.setVideoContentMode(self.currentResizeMode)

            if let currentVideoView = self.currentVideoView {
                currentVideoView.removeFromSuperview()
                self.currentVideoView = nil
            }
            videoView.initialGravity = self.currentResizeMode
            self.currentVideoView = videoView
            self.addSubview(videoView, positioned: .below, relativeTo: self.shadowView)
            self.updateLayout(size: self.frame.size, transition: transition)
            

            
//            self.call.makeVideoView(endpointId: peer.endpointId, videoMode: videoMode, completion: { [weak self] videoView in
//                guard let strongSelf = self, let videoView = videoView else {
//                    return
//                }
//
//
//            })
        } else {
            if let currentVideoView = self.currentVideoView {
                currentVideoView.removeFromSuperview()
                self.currentVideoView = nil
            }
        }
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.validLayout = size
        if let currentVideoView = self.currentVideoView {
            transition.updateFrame(view: currentVideoView, frame: bounds)
            currentVideoView.updateLayout(size: size, transition: transition)
        }
        transition.updateFrame(view: shadowView, frame: CGRect(origin: NSMakePoint(0, size.height - 50), size: NSMakeSize(size.width, 50)))
        transition.updateFrame(view: gravityButton, frame: CGRect(origin: NSMakePoint(size.width - 10 - gravityButton.frame.width, size.height - 10 - gravityButton.frame.height), size: gravityButton.frame.size))
        
        
        self.nameView.resize(size.width - 20)
        self.statusView.resize(size.width - 30 - self.nameView.frame.width)

        
        transition.updateFrame(view: self.nameView, frame: CGRect(origin: NSMakePoint(10, size.height - 10 - self.nameView.frame.height), size: self.nameView.frame.size))
        transition.updateFrame(view: self.statusView, frame: CGRect(origin: NSMakePoint(self.nameView.frame.maxX + 10, self.nameView.frame.minY), size: self.statusView.frame.size))
        

        transition.updateFrame(view: speakingView, frame: bounds)
    }
    
    deinit {
        audioLevelDisposable.dispose()
    }
    
    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
}
