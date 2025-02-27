import SwiftUI
import SwiftData
import CoreNFC

struct NFCMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var memoryDataList: [NFCMemoryData]
    @StateObject private var nfcManager = NFCManager()
    
    @State private var showingAddSheet = false
    @State private var newName = ""
    @State private var newData = ""
    @State private var selectedData: NFCMemoryData?
    @State private var isValidData = true
    
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(memoryDataList) { memoryData in
                        VStack(alignment: .leading) {
                            Text(memoryData.name)
                                .font(.headline)
                            Text(memoryData.data)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Created: \(memoryData.timestamp, format: .dateTime)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedData = memoryData
                        }
                    }
                    .onDelete(perform: deleteMemoryData)
                }
                
                if let selected = selectedData {
                    VStack(spacing: 15) {
                        Text("Selected: \(selected.name)")
                            .font(.headline)
                        
                        Text(selected.data)
                            .font(.subheadline)
                            .padding(.bottom)
                        
                        Button(action: {
                            writeSelectedData()
                        }) {
                            Text("Write to NFC Tag")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(nfcManager.isScanning)
                        
                        Text(nfcManager.message)
                            .foregroundStyle(nfcManager.isScanning ? .blue : .secondary)
                            .padding(.top)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("NFC Memory Writer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Memory Data", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Memory Data Details")) {
                            TextField("Name", text: $newName)
                            
                            TextField("Data (format: 00:01:02:03...)", text: $newData)
                                .onChange(of: newData) {
                                    validateData()
                                }
                            
                            if !isValidData {
                                Text("Invalid format. Use hexadecimal values separated by colons.")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    .navigationTitle("Add Memory Data")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddSheet = false
                                resetForm()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                addMemoryData()
                                showingAddSheet = false
                            }
                            .disabled(newName.isEmpty || newData.isEmpty || !isValidData)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
    
    private func addMemoryData() {
        let newMemoryData = NFCMemoryData(name: newName, data: newData)
        modelContext.insert(newMemoryData)
        resetForm()
    }
    
    private func deleteMemoryData(offsets: IndexSet) {
        for index in offsets {
            let data = memoryDataList[index]
            modelContext.delete(data)
            
            // Deselect if the deleted item is selected
            if selectedData?.id == data.id {
                selectedData = nil
            }
        }
    }
    
    private func writeSelectedData() {
        guard let selected = selectedData else { return }
        let byteArray = selected.toByteArray()
        nfcManager.startScanning(data: byteArray)
    }
    
    private func resetForm() {
        newName = ""
        newData = ""
        isValidData = true
    }
    
    private func validateData() {
        let pattern = "^([0-9A-Fa-f]{2}:)+([0-9A-Fa-f]{2})$|^[0-9A-Fa-f]{2}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        isValidData = predicate.evaluate(with: newData) || newData.isEmpty
    }
}

#Preview {
    NFCMemoryView()
        .modelContainer(for: NFCMemoryData.self, inMemory: true)
}
