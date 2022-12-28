// VoiceNote+SpeechResult.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func voiceNoteSpeechResult(for voiceNote: VoiceNote) -> some View {
        Text(recognizedText)
            .transition(.scale.combined(with: .opacity))
            .matchedGeometryEffect(id: recognizedTextId, in: voiceNoteNamespace)
            .if(recognizeSpeech && !recognized) {
                $0.onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                    Task {
                        guard let message = await viewModel.tdGetMessage(id: customMessage.message.id),
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
                                        logger.log("Error recognizing words: \(speechRecognitionResultError.error)")
                                        recognizedText = "No words recognized"
                                        recognized = true
                                }
                            }
                        }
                    }
                }
            }
        
    }
}
