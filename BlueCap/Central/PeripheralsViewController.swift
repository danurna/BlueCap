//
//  PeripheralsViewController.swift
//  BlueCapUI
//
//  Created by Troy Stribling on 6/5/14.
//  Copyright (c) 2014 gnos.us. All rights reserved.
//

import UIKit
import CoreBluetooth
import BlueCapKit

let MAX_FAILED_RECONNECTS = 0

class PeripheralsViewController : UITableViewController {
    
    var stopScanBarButtonItem   : UIBarButtonItem!
    var startScanBarButtonItem  : UIBarButtonItem!
    var connectionSequence      : Dictionary<Peripheral, Int> = [:]
    
    struct MainStoryboard {
        static let peripheralCell = "PeripheralCell"
    }
    
    required init(coder aDecoder:NSCoder) {
        super.init(coder:aDecoder)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title:"", style:.Bordered, target:nil, action:nil)
        self.stopScanBarButtonItem = UIBarButtonItem(barButtonSystemItem:.Stop, target:self, action:"toggleScan:")
        self.startScanBarButtonItem = UIBarButtonItem(barButtonSystemItem:.Refresh, target:self, action:"toggleScan:")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setScanButton()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prepareForSegue(segue:UIStoryboardSegue!, sender:AnyObject!) {
        if segue.identifier == "PeripheralDetail" {
            let selectedIndex = self.tableView.indexPathForCell(sender as UITableViewCell)
            let viewController = segue.destinationViewController as PeripheralViewController
            viewController.peripheral = CentralManager.sharedInstance().peripherals[selectedIndex.row]
        }
    }
    
    override func shouldPerformSegueWithIdentifier(identifier:String!, sender:AnyObject!) -> Bool {
        var perform = false
        if identifier == "PeripheralDetail" {
            let selectedIndex = self.tableView.indexPathForCell(sender as UITableViewCell)
            let peripheral = CentralManager.sharedInstance().peripherals[selectedIndex.row]
            if peripheral.state == .Connected {
                perform = true
            }
        }
        return perform
    }
    
    // actions
    @IBAction func toggleScan(sender:AnyObject) {
        Logger.debug("toggleScan")
        let central = CentralManager.sharedInstance()
        if (central.isScanning) {
            if ConfigStore.getRegionScanEnabled() {
                self.stopMonitoringRegions()
                RegionScannerator.sharedInstance().stopScanning()
            } else {
                central.stopScanning()
            }
            self.setScanButton()
            central.disconnectAllPeripherals()
        } else {
            central.powerOn(){
                Logger.debug("powerOn Callback")
                self.startScan()
                self.setScanButton()
            }
        }
    }
    
    // UITableViewDataSource
    override func numberOfSectionsInTableView(tableView:UITableView!) -> Int {
        return 1
    }
    
    override func tableView(_:UITableView!, numberOfRowsInSection section:Int) -> Int {
        return CentralManager.sharedInstance().peripherals.count
    }
    
    override func tableView(tableView: UITableView!, cellForRowAtIndexPath indexPath: NSIndexPath!) -> UITableViewCell! {
        let cell = tableView.dequeueReusableCellWithIdentifier(MainStoryboard.peripheralCell, forIndexPath: indexPath) as PeripheralCell
        let peripheral = CentralManager.sharedInstance().peripherals[indexPath.row]
        cell.nameLabel.text = peripheral.name
        switch(peripheral.state) {
        case .Connected:
            cell.connectingActivityIndicator.stopAnimating()
            cell.accessoryType = .DetailButton
        default:
            cell.connectingActivityIndicator.startAnimating()
            cell.accessoryType = .None
        }
        return cell
    }
    
    // UITableViewDelegate
    func setScanButton() {
        if (CentralManager.sharedInstance().isScanning) {
            self.navigationItem.setRightBarButtonItem(self.stopScanBarButtonItem, animated:false)
        } else {
            self.navigationItem.setRightBarButtonItem(self.startScanBarButtonItem, animated:false)
        }
    }
    
    // utils
    func connect(peripheral:Peripheral) {
        peripheral.connect(Connectorator() {(connectorator:Connectorator) -> () in
            connectorator.disconnect = {(periphear:Peripheral) -> () in
                Logger.debug("PeripheralsViewController#onDisconnect")
                peripheral.reconnect()
                self.tableView.reloadData()
            }
            connectorator.connect = {(peipheral:Peripheral) -> () in
                Logger.debug("PeripheralsViewController#onConnect")
                self.tableView.reloadData()
            }
            connectorator.timeout = {(peripheral:Peripheral) -> () in
                Logger.debug("PeripheralsViewController#onTimeout")
                peripheral.reconnect()
                self.tableView.reloadData()
            }
            connectorator.forceDisconnect = {(peripheral:Peripheral) -> () in
                Logger.debug("PeripheralsViewController#onForcedDisconnect")
                self.tableView.reloadData()
            }
        })
    }
    
    func startScan() {
        let scanMode = ConfigStore.getScanMode()
        let afterPeripheralDiscovered = {(peripheral:Peripheral, rssi:Int) -> () in
            self.connect(peripheral)
        }
        let afterTimeout = {
            self.setScanButton()
        }
        // Region Scan Enabled
        if ConfigStore.getRegionScanEnabled() {
            switch scanMode {
            // Region Promiscuous Scan Enabled
            case "Promiscuous" :
                // Region Promiscuous Scan with Timeout Enabled
                if ConfigStore.getScanTimeoutEnabled() {
                    RegionScannerator.sharedInstance().startScanning(Float(ConfigStore.getScanTimeout()), afterPeripheralDiscovered:afterPeripheralDiscovered, afterTimeout:afterTimeout)
                } else {
                    RegionScannerator.sharedInstance().startScanning(afterPeripheralDiscovered)
                }
                self.startMonitoringRegions()
                break
            // Region Service Scan Enabled
            case "Service" :
                let scannedServices = ConfigStore.getScannedServices()
                if scannedServices.isEmpty {
                    self.presentViewController(UIAlertController.alertOnError("No scan services configured"), animated:true, completion:nil)
                } else {
                    // Region Service Scan with Timeout Enabled
                    if ConfigStore.getScanTimeoutEnabled() {
                        RegionScannerator.sharedInstance().startScanningForServiceUUIDs(Float(ConfigStore.getScanTimeout()), uuids:scannedServices,
                            afterPeripheralDiscoveredCallback:afterPeripheralDiscovered, afterTimeout:afterTimeout)
                    } else {
                        RegionScannerator.sharedInstance().startScanningForServiceUUIDs(scannedServices, afterPeripheralDiscovered:afterPeripheralDiscovered)
                    }
                    self.startMonitoringRegions()
                }
                break
            default:
                Logger.debug("Scan Mode :'\(scanMode)' invalid")
                break
            }
        } else {
            // Promiscuous Scan Enabled
            switch scanMode {
            case "Promiscuous" :
                // Promiscuous Scan with Timeout Enabled
                if ConfigStore.getScanTimeoutEnabled() {
                    TimedScannerator.sharedInstance().startScanning(Float(ConfigStore.getScanTimeout()), afterPeripheralDiscovered:afterPeripheralDiscovered, afterTimeout:afterTimeout)
                } else {
                    CentralManager.sharedInstance().startScanning(afterPeripheralDiscovered)                }
                break
            case "Service" :
                let scannedServices = ConfigStore.getScannedServices()
                if scannedServices.isEmpty {
                    self.presentViewController(UIAlertController.alertOnError("No scan services configured"), animated:true, completion:nil)
                } else {
                    // Service Scan with Timeout Enabled
                    if ConfigStore.getScanTimeoutEnabled() {
                        TimedScannerator.sharedInstance().startScanningForServiceUUIDs(Float(ConfigStore.getScanTimeout()), uuids:scannedServices,
                            afterPeripheralDiscoveredCallback:afterPeripheralDiscovered, afterTimeout:afterTimeout)
                    } else {
                        CentralManager.sharedInstance().startScanningForServiceUUIDs(scannedServices, afterPeripheralDiscovered:afterPeripheralDiscovered)
                    }
                }
                break
            default:
                Logger.debug("Scan Mode :'\(scanMode)' invalid")
                break
            }
        }
    }
    
    func startMonitoringRegions() {
        for (name, location) in ConfigStore.getScanRegions() {
            RegionScannerator.sharedInstance().startMonitoringForRegion(RegionMonitor(center:location, identifier:name) {(regionMonitor) in
                regionMonitor.exitRegion = {
                    CentralManager.sharedInstance().stopScanning()
                    self.presentViewController(UIAlertController.alertWithMessage("Exiting Region"), animated:true, completion:nil)
                }
                regionMonitor.enterRegion = {
                    self.presentViewController(UIAlertController.alertWithMessage("Entering Region"), animated:true, completion:nil)
                    let services = ConfigStore.getScannedServices()
                    let afterPeripheralDiscovered = {(peripheral:Peripheral, rssi:Int) -> () in
                        self.connect(peripheral)
                    }
                    if  services.isEmpty {
                        CentralManager.sharedInstance().startScanning(afterPeripheralDiscovered)
                    } else {
                        CentralManager.sharedInstance().startScanningForServiceUUIDs(services, afterPeripheralDiscovered:afterPeripheralDiscovered)
                    }
                }
                regionMonitor.startMonitoringRegion = {
                }
            })
        }
    }
    
    func stopMonitoringRegions() {
        for regionMonitors in RegionScannerator.sharedInstance().regionMonitors {
            RegionScannerator.sharedInstance().stopMonitoringForRegion(regionMonitors)
        }
    }

}