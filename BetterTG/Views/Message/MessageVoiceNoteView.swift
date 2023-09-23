// MessageVoiceNoteView.swift

import TDLibKit

// swiftlint:disable:next type_body_length
struct MessageVoiceNoteView: View {
    let voiceNote: VoiceNote
    let message: Message
    let isOutgoing: Bool
    
    init(voiceNote: VoiceNote, message: Message) {
        self.voiceNote = voiceNote
        self.message = message
        self.isOutgoing = message.isOutgoing
    }
    
    @Environment(ChatViewModel.self) var viewModel
    
    let recognizedTextId = "recognizedTextId"
    let playId = "playId"
    let currentTimeId = "currentTimeId"
    let durationId = "durationId"
    let chevronId = "chevronId"
    let speechId = "speechId"
    
    @State var recognized = false
    @State var recognizedText = "..."
    @State var isListeningVoiceNote = false
    @State var recognizeSpeech = false
    
    @Namespace var namespace
    
    var body: some View {
        AsyncTdFile(id: voiceNote.voice.id) { voice in
            Group {
                if isListeningVoiceNote, viewModel.savedMediaPath == voice.local.path {
                    voiceNoteViewExpanded(voice.local.path, from: voiceNote)
                } else {
                    voiceNoteView(voice.local.path, from: voiceNote)
                }
            }
            .onReceive(nc.publisher(for: .localIsListeningVoice)) { notification in
                guard let value = notification.object as? (isListening: Bool, path: String) else { return }
                if voice.local.path != value.path {
                    isListeningVoiceNote = value.isListening
                }
            }
        } placeholder: {
            voiceNoteView(from: voiceNote)
        }
        .padding(5)
        .onChange(of: isListeningVoiceNote) {
            nc.post(name: .localIsListeningVoice, object: nil)
        }
        .onChange(of: recognizeSpeech) {
            nc.post(name: .localRecognizeSpeech, object: nil)
        }
    }
    
    @ViewBuilder func voiceNoteView(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        VStack(alignment: .center, spacing: 5) {
            voiceNoteViewTop(path, from: voiceNote)
            
            voiceNoteViewBottom(path, from: voiceNote)
            
            if recognizeSpeech {
                voiceNoteSpeechResult(for: voiceNote)
            }
        }
    }
    
    @ViewBuilder func voiceNoteViewTop(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 5) {
            if recognizeSpeech { Spacer() }
            
            if isOutgoing {
                voiceNoteChevron(expanded: false, path: path, duration: voiceNote.duration)
            } else {
                voiceNoteSpeech(for: voiceNote)
            }
            
            if recognizeSpeech { Spacer() }
            
            Group {
                if path == nil {
                    Image(systemName: "xmark")
                } else {
                    if viewModel.savedMediaPath == path && viewModel.isPlaying {
                        Image(systemName: "pause.fill")
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
            }
            .font(.largeTitle)
            .transition(.scale)
            .matchedGeometryEffect(id: playId, in: namespace)
            .onTapGesture {
                if let path {
                    viewModel.mediaToggle(with: path, duration: voiceNote.duration)
                }
            }
            
            if recognizeSpeech { Spacer() }
            
            if isOutgoing {
                voiceNoteSpeech(for: voiceNote)
            } else {
                voiceNoteChevron(expanded: false, path: path, duration: voiceNote.duration)
            }
            
            if recognizeSpeech { Spacer() }
        }
    }
    
    @ViewBuilder func voiceNoteViewBottom(_ path: String? = nil, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text((viewModel.savedMediaPath == path ? formattedDuration(from: viewModel.currentTime) : "0:00"))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: currentTimeId, in: namespace)
            
            Text(" / ")
            
            Text(formattedDuration(from: voiceNote.duration))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: durationId, in: namespace)
        }
        .font(.caption)
        .foregroundColor(.white).opacity(0.5)
    }
    
    @ViewBuilder func voiceNoteViewExpanded(_ path: String, from voiceNote: VoiceNote) -> some View {
        VStack(alignment: .center, spacing: 10) {
            voiceNoteViewExpandedTop(path, from: voiceNote)
            
            voiceNoteViewExpandedBottom(for: voiceNote)
            
            if recognizeSpeech {
                voiceNoteSpeechResult(for: voiceNote)
            }
        }
    }
    
    @ViewBuilder func voiceNoteViewExpandedTop(_ path: String, from voiceNote: VoiceNote) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()
            
            if isOutgoing {
                voiceNoteChevron(expanded: true, duration: voiceNote.duration)
            } else {
                voiceNoteSpeech(for: voiceNote)
            }
            
            SpacingAround {
                Image(systemName: "gobackward.5")
                    .font(.title)
                    .onTapGesture {
                        viewModel.mediaSeekBackward()
                    }
            }
            
            Group {
                if viewModel.isPlaying {
                    Image(systemName: "pause.fill")
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .font(.system(size: 40, weight: .bold))
            .transition(.scale)
            .matchedGeometryEffect(id: playId, in: namespace)
            .onTapGesture {
                viewModel.mediaToggle(with: path, duration: voiceNote.duration)
            }
            
            SpacingAround {
                Image(systemName: "goforward.5")
                    .font(.title)
                    .onTapGesture {
                        viewModel.mediaSeekForward()
                    }
            }
            
            if isOutgoing {
                voiceNoteSpeech(for: voiceNote)
            } else {
                voiceNoteChevron(expanded: true, duration: voiceNote.duration)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder func voiceNoteViewExpandedBottom(for voiceNote: VoiceNote) -> some View {
        @Bindable var viewModel = viewModel
        Slider(value: $viewModel.timeSliderValue, in: 0...Double(voiceNote.duration)) {
            Text("Voice Note Time Slider")
        } onEditingChanged: { value in
            if !value {
                viewModel.mediaSeekTo()
            } else {
                viewModel.isSeeking = true
            }
        }
        .padding(.horizontal, 10)
        
        HStack(alignment: .center, spacing: 0) {
            Text(viewModel.isSeeking
                 ? formattedDuration(from: viewModel.timeSliderValue)
                 : formattedDuration(from: viewModel.currentTime)
            )
            .fixedSize(horizontal: true, vertical: false)
            .matchedGeometryEffect(id: currentTimeId, in: namespace)
            
            Spacer()
            
            Text(formattedDuration(from: voiceNote.duration))
                .fixedSize(horizontal: true, vertical: false)
                .matchedGeometryEffect(id: durationId, in: namespace)
        }
        .padding(.horizontal, 10)
        .foregroundColor(.white.opacity(0.5))
    }
    
    @ViewBuilder func voiceNoteChevron(expanded: Bool, path: String? = nil, duration: Int) -> some View {
        Image(systemName: (isOutgoing && expanded) || (!isOutgoing && !expanded) ? "chevron.right" : "chevron.left")
            .font(.title)
            .matchedGeometryEffect(id: chevronId, in: namespace)
            .onTapGesture {
                if expanded {
                    withAnimation {
                        isListeningVoiceNote = false
                    }
                } else if let path {
                    if path != viewModel.savedMediaPath {
                        viewModel.mediaToggle(with: path, duration: duration)
                    }
                    withAnimation {
                        isListeningVoiceNote = true
                    }
                }
            }
    }
    
    @ViewBuilder func voiceNoteSpeech(for voiceNote: VoiceNote) -> some View {
        Image(systemName: "a.square")
            .font(.title)
            .matchedGeometryEffect(id: speechId, in: namespace)
            .onTapGesture {
                Task {
                    await viewModel.tdRecognizeSpeech(for: message.id)
                }
                
                withAnimation {
                    if let recognition = voiceNote.speechRecognitionResult {
                        switch recognition {
                            case .speechRecognitionResultError(let speechRecognitionResultError):
                                log("Error recognizing words: \(speechRecognitionResultError)")
                                recognizedText = "No words recognized"
                                recognized = true
                            case .speechRecognitionResultText(let speechRecognitionResultText):
                                recognizedText = speechRecognitionResultText.text
                                recognized = true
                            default:
                                break
                        }
                    }
                    
                    recognizeSpeech.toggle()
                }
            }
    }
    
    @ViewBuilder func voiceNoteSpeechResult(for voiceNote: VoiceNote) -> some View {
        Text(recognizedText)
            .transition(.scale.combined(with: .opacity))
            .matchedGeometryEffect(id: recognizedTextId, in: namespace)
            .if(recognizeSpeech && !recognized) {
                $0.onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                    Task {
                        guard let message = await viewModel.tdGetMessage(id: message.id),
                              case .messageVoiceNote(let messageVoiceNote) = message.content,
                              let result = messageVoiceNote.voiceNote.speechRecognitionResult
                        else { return }
                        
                        await MainActor.run {
                            withAnimation {
                                switch result {
                                    case .speechRecognitionResultPending(let speechRecognitionResultPending):
                                        recognizedText = "\(speechRecognitionResultPending.partialText)..."
                                    case .speechRecognitionResultText(let speechRecognitionResultText):
                                        recognizedText = speechRecognitionResultText.text
                                        recognized = true
                                    case .speechRecognitionResultError(let speechRecognitionResultError):
                                        log("Error recognizing words: \(speechRecognitionResultError.error)")
                                        recognizedText = "No words recognized"
                                        recognized = true
                                }
                            }
                        }
                    }
                }
            }
    }
    
    func formattedDuration(from duration: Double) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }
    
    func formattedDuration<T: BinaryInteger>(from duration: T) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }
}
