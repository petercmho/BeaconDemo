//
//  ViewController.swift
//  BeaconDemo
//
//  Created by Peter Ho on 2017-01-14.
//  Copyright © 2017 Peter Ho. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UITableViewController, CBCentralManagerDelegate {
    static let BEACON_CODE_INDEX = 2
    static let BEACON_CODE_VALUE = 0xbeac
    static let UUID_START = 4
    static let UUID_STOP = 19
    static let CONTENT_START = 20
    static let CONTENT_STOP = 23
    static let REFERENCE_RSSI_START = 24
    static let BEACON_DURATION = 8.5
    
    static var options: [String : Any]?
    var beacons = [BeaconModel]()
    var bleManager: CBCentralManager?
    private var timer: Timer?

    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        let test = BeaconModel()
//        test.uuid = "001122-3344-5566-7788-99001122"
//        test.arg1 = 0x1ff
//        test.arg2 = 0xff01
//        test.referenceRssi = -58
//        test.currentRssi = -48
//        beacons.append(test)
        bleManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.timer?.invalidate()
        self.timer = nil
        
        self.stopScanning()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.startScanning()
        
        self.timer = Timer.scheduledTimer(timeInterval: 4.3, target: self, selector: #selector(repeatableValidationTask), userInfo: nil, repeats: true)
        self.timer?.fire()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: UITableViewDataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return beacons.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BeaconItemCell", for: indexPath)
        let beacon = self.beacons[indexPath.row]
        
        cell.textLabel?.text = beacon.uuid
        let arg1 = String(format: "%04x", beacon.arg1! & 0xffff)
        let arg2 = String(format: "%04x", beacon.arg2! & 0xffff)
        cell.detailTextLabel?.text = "arg1: \(arg1) arg2: \(arg2) RSSI: \(beacon.currentRssi!) TxPower: \(beacon.referenceRssi!)"
        return cell
    }
    
    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            self.startScanning()
        }
        else {
            self.stopScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // reporting callback
        print("Peripheral is \(peripheral.name)")
        
        if let services = peripheral.services {
            for s in services {
                
                if let charactistics = s.characteristics {
                    for c in charactistics {

                    }
                }
            }
        }
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            let bytes = data.withUnsafeBytes{
                Array(UnsafeBufferPointer<UInt8>(start: $0, count: data.count/MemoryLayout<UInt8>.size))
            }
            if bytes.count < ViewController.REFERENCE_RSSI_START {
                print("Unknown CBAdvertisementDataManufacturerDataKey - byte size is \(bytes.count)")
                return
            }
            let code:Int = (Int(bytes[ViewController.BEACON_CODE_INDEX]) << 8) + Int(bytes[ViewController.BEACON_CODE_INDEX+1])
            if code != ViewController.BEACON_CODE_VALUE {
                let hexString = data.map { String(format: "%02hhx ", $0) }.joined()
                print("CBAdvertisementDataManufactureDataKey - \(hexString)")
                return
            }
            
            let beaconId = peripheral.identifier.uuidString
            
            var beacon: BeaconModel? = nil
            for b in beacons {
                if b.beaconId == beaconId {
                    beacon = b
                    break
                }
            }
            if beacon == nil {
                beacon = BeaconModel()
                beacon?.beaconId = beaconId
                beacon?.referenceRssi = Int(bytes[ViewController.REFERENCE_RSSI_START] & 0xff) - 256
                beacon?.arg1 = ((UInt16(bytes[ViewController.CONTENT_START]) << 8) & 0xff00) + (UInt16(bytes[ViewController.CONTENT_START+1]) & 0xff)
                beacon?.arg2 = ((UInt16(bytes[ViewController.CONTENT_START+2]) << 8) & 0xff00) + (UInt16(bytes[ViewController.CONTENT_START+3]) & 0xff)
                beacon?.uuid = getBeaconUuidFromAdvertisement(bytes)
                self.beacons.append(beacon!)
            }
            
            // update current RSSI field and timestamp
            beacon!.currentRssi = RSSI.intValue
            beacon!.timestamp = NSDate().timeIntervalSince1970
            
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Beacon helper methods
    
    func getBeaconUuidFromAdvertisement(_ adv: [UInt8]?) -> String {
        var uuid = String()
        var offset = 0
        for i in ViewController.UUID_START...ViewController.UUID_STOP {
            uuid = uuid.appendingFormat("%02x", adv![i] & 0xff)
            if offset == 3 || offset == 5 || offset == 7 || offset == 9 {
                uuid.append("-")
            }
            offset += 1
        }
        
        return uuid
    }
    
    func validateBeacons() -> Bool {
        var anythingWasRemoved = false
        let earliestTimestampAllowed = NSDate().timeIntervalSince1970 - ViewController.BEACON_DURATION
        
        var newArray = [BeaconModel]()
        
        for beacon in self.beacons {
            if beacon.timestamp! >= earliestTimestampAllowed {
                newArray.append(beacon)
            }
            else {
                anythingWasRemoved = true
            }
        }
        
        if anythingWasRemoved {
            beacons = newArray
        }
        
        return anythingWasRemoved
    }
    
    func repeatableValidationTask(_ theTimer: Timer) {
        if self.validateBeacons() {
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Bluetooth Scanning
    func startScanning() {
        if ViewController.options == nil {
            ViewController.options = [String : Any]()
            ViewController.options?[CBCentralManagerScanOptionAllowDuplicatesKey] = NSNumber(booleanLiteral: true)
        }
        bleManager?.scanForPeripherals(withServices: nil, options: ViewController.options)
    }
    
    func stopScanning() {
        bleManager?.stopScan()
    }
}

