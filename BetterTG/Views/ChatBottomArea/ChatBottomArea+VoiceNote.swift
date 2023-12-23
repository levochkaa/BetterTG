// ChatBottomArea+VoiceNote.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var voiceNoteRecording: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                withAnimation {
                    try? FileManager.default.removeItem(at: viewModel.savedVoiceNoteUrl)
                    viewModel.audioRecorder.stop()
                    viewModel.recordingVoiceNote = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22))
                    .contentShape(Rectangle())
            }
            
            Spacer()
            Text(formattedTimerCount)
            Spacer()
            
            rightSide
        }
        .padding(.vertical, 2)
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }
    
    var formattedTimerCount: String {
        let time = String(format: "%.2f", timerCount).split(separator: ".", maxSplits: 2)
        let seconds = Int(time[0]) ?? 0
        var resultString = ""
        if seconds >= 60 {
            resultString += "\(seconds / 60):" // seconds / 60 == minutes
            var estimatedSeconds = String(seconds % 60)
            if estimatedSeconds.count == 1 { estimatedSeconds = "0\(estimatedSeconds)" }
            resultString += "\(estimatedSeconds)"
        } else {
            resultString += "\(seconds).\(time[1])" // time[1] == millisecongs
        }
        return resultString
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            viewModel.audioRecorder.updateMeters()
            wave.append(viewModel.audioRecorder.peakPower(forChannel: 0))
            timerCount += timer.timeInterval
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
    }
}
