/**
 Copyright (C) 2016  Johan Degraeve
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/gpl.txt>.
 
 */
package services
{
	import com.distriqt.extension.bluetoothle.AuthorisationStatus;
	import com.distriqt.extension.bluetoothle.BluetoothLE;
	import com.distriqt.extension.bluetoothle.BluetoothLEState;
	import com.distriqt.extension.bluetoothle.events.BluetoothLEEvent;
	import com.distriqt.extension.bluetoothle.events.CharacteristicEvent;
	import com.distriqt.extension.bluetoothle.events.PeripheralEvent;
	import com.distriqt.extension.bluetoothle.objects.Characteristic;
	import com.distriqt.extension.bluetoothle.objects.Peripheral;
	import com.distriqt.extension.notifications.Notifications;
	import com.distriqt.extension.notifications.builders.NotificationBuilder;
	import com.distriqt.extension.notifications.events.NotificationEvent;
	import com.freshplanet.ane.AirBackgroundFetch.BackgroundFetch;
	import com.freshplanet.ane.AirBackgroundFetch.BackgroundFetchEvent;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;
	
	import G5Model.AuthChallengeRxMessage;
	import G5Model.AuthChallengeTxMessage;
	import G5Model.AuthRequestTxMessage;
	import G5Model.AuthStatusRxMessage;
	import G5Model.BatteryInfoRxMessage;
	import G5Model.BatteryInfoTxMessage;
	import G5Model.SensorRxMessage;
	import G5Model.SensorTxMessage;
	
	import database.BgReading;
	import database.BlueToothDevice;
	import database.CommonSettings;
	import database.LocalSettings;
	
	import distriqtkey.DistriqtKey;
	
	import events.BlueToothServiceEvent;
	import events.NotificationServiceEvent;
	import events.SettingsServiceEvent;
	
	import feathers.controls.Alert;
	
	import model.ModelLocator;
	import model.Tomato;
	import model.TransmitterDataBluKonPacket;
	import model.TransmitterDataBlueReaderBatteryPacket;
	import model.TransmitterDataBlueReaderPacket;
	import model.TransmitterDataG5Packet;
	import model.TransmitterDataTransmiter_PLPacket;
	import model.TransmitterDataXBridgeBeaconPacket;
	import model.TransmitterDataXBridgeDataPacket;
	import model.TransmitterDataXBridgeRDataPacket;
	import model.TransmitterDataXdripDataPacket;
	
	import starling.events.Event;
	
	import ui.popups.AlertManager;
	import ui.popups.G4WixelSender;
	
	import utils.BadgeBuilder;
	import utils.Trace;
	import utils.UniqueId;
	import utils.libre.LibreAlarmReceiver;
	
	/**
	 * all functionality related to bluetooth connectivity<br>
	 * init function must be called once immediately at start of the application<br>
	 * <br>
	 * to get info about connectivity status, new transmitter data ... check BluetoothServiceEvent  create listeners for the events<br>
	 * BluetoothService itself is not doing anything with the data received from the bluetoothdevice, also not checking the transmit id, it just passes the information via 
	 * dispatching<br>
	 */
	public class BluetoothService extends EventDispatcher
	{
		[ResourceBundle("globaltranslations")]
		[ResourceBundle("bluetoothservice")]
		
		private static var _instance:BluetoothService = new BluetoothService();
		public static function get instance():BluetoothService
		{
			return _instance;
		}
		private static var initialStart:Boolean = true;
		
		//needed for en- decoding G4 transmitter id
		private static const srcNameTable:Array = [ '0', '1', '2', '3', '4', '5', '6', '7',
			'8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
			'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
			'Q', 'R', 'S', 'T', 'U', 'W', 'X', 'Y' ];

		
		//All UUD's used in bluetooth communication for different peripheral types
		//xdrip UUID's
		private static const G4_Service_UUID:String = "0000FFE0-0000-1000-8000-00805F9B34FB"; 
		private static const G4_RX_Characteristic_UUID:String = "0000FFE1-0000-1000-8000-00805F9B34Fb";
		private static const G4_TX_Characteristic_UUID:String = G4_RX_Characteristic_UUID;
		private static const G4_Advertisement_UUID:String = G4_Service_UUID;
		private static const G4_Characteristics_UUID_Vector:Vector.<String> = new <String>[G4_RX_Characteristic_UUID];
		
		//G5 UUID's
		private static const G5_Service_UUID:String = "F8083532-849E-531C-C594-30F1F86A4EA5"; 
		//private static const G5_Communication_Characteristic_UUID:String = "F8083533-849E-531C-C594-30F1F86A4EA5";//not used for the moment
		private static const G5_Control_Characteristic_UUID:String = "F8083534-849E-531C-C594-30F1F86A4EA5";
		private static const G5_Authentication_Characteristic_UUID:String = "F8083535-849E-531C-C594-30F1F86A4EA5";
		private static const G5_Advertisement_UUID:String = "0000FEBC-0000-1000-8000-00805F9B34FB";
		private static const G5_Characteristics_UUID_Vector:Vector.<String> = new <String>[G5_Authentication_Characteristic_UUID, G5_Control_Characteristic_UUID];
		
		//Blucon UUID's
		private static const Blucon_Service_UUID:String = "436A62C0-082E-4CE8-A08B-01D81F195B24"; 
		private static const Blucon_RX_Characteristic_UUID:String = "436A0C82-082E-4CE8-A08B-01D81F195B24";
		private static const Blucon_TX_Characteristic_UUID:String = "436AA6E9-082E-4CE8-A08B-01D81F195B24";
		private static const Blucon_Advertisement_UUID:String = Blucon_Service_UUID;
		private static const Blucon_Characteristics_UUID_Vector:Vector.<String> = new <String>[Blucon_RX_Characteristic_UUID, Blucon_TX_Characteristic_UUID];
		
		//Bluereader UUID's
		private static const BlueReader_Service_UUID:String = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
		private static const BlueReader_RX_Characteristic_UUID:String = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
		private static const BlueReader_TX_Characteristic_UUID:String = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
		private static const BlueReader_Advertisement_UUID:String = "";
		private static const BlueReader_Characteristics_UUID_Vector:Vector.<String> = new <String>[BlueReader_TX_Characteristic_UUID, BlueReader_RX_Characteristic_UUID];
		
		//Transmiter PL UUID's
		private static const Transmiter_PL_Service_UUID:String = "C97433F0-BE8F-4DC8-B6F0-5343E6100EB4";
		private static const Transmiter_PL_RX_Characteristic_UUID:String = "C97433F1-BE8F-4DC8-B6F0-5343E6100EB4";
		private static const Transmiter_PL_TX_Characteristic_UUID:String = "C97433F2-BE8F-4DC8-B6F0-5343E6100EB4";
		private static const Transmiter_PL_Advertisement_UUID:String = Transmiter_PL_Service_UUID;
		private static const Transmiter_PL_Characteristics_UUID_Vector:Vector.<String> = new <String>[Transmiter_PL_RX_Characteristic_UUID, Transmiter_PL_TX_Characteristic_UUID];
		
		//xbridger uses the same uuid's as xdrip except for TX Characteristic
		private static const xBridgeR_Service_UUID:String = "0000FFE0-0000-1000-8000-00805F9B34FB"; 
		private static const xBridgeR_RX_Characteristic_UUID:String = "0000FFE1-0000-1000-8000-00805F9B34FB";
		private static const xBridgeR_TX_Characteristic_UUID:String = "0000FFE2-0000-1000-8000-00805F9B34FB";
		private static const xBridgeR_Advertisement_UUID:String = xBridgeR_Service_UUID;
		private static const xBridgeR_Characteristics_UUID_Vector:Vector.<String> = new <String>[xBridgeR_RX_Characteristic_UUID];
		
		//Following variables with get value which is dependent on peripheral type
		/**
		 * the service_UUID to use for the selected devicetype 
		 */
		private static var service_UUID:String = "";
		/**
		 * advertisement uuid vector for the selectecd devicetype
		 */
		private static var advertisement_UUID_Vector:Vector.<String>;
		/**
		 * chararacteristics uuid to use for the selected devicetype
		 */
		private static var characteristics_UUID_Vector:Vector.<String>;
		/**
		 * Receive characteristic UUID for the selectecd devicetype
		 */
		private static var RX_Characteristic_UUID:String;
		/**
		 * Transmit characteristic UUID for the selectecd devicetype
		 */
		private static var TX_Characteristic_UUID:String;
		/**
		 * service UUID vector for the selectecd devicetype
		 */
		private static var service_UUID_Vector:Vector.<String>;

		/**
		 * the read characteristic to be used for all types of peripheral. For G5 this is used as authentication characteristics
		 */
		private static var readCharacteristic:Characteristic;
		
		/**
		 * the write characteristic to be used for all types of peripheral. For G5 this is used as control characteristics 
		 */
		private static var writeCharacteristic:Characteristic;
		
		//generic global variables needed for bluetooth communications
		private static var connectionAttemptTimeStamp:Number;
		private static const maxTimeBetweenConnectAttemptAndConnectSuccess:Number = 3;
		private static var waitingForPeripheralCharacteristicsDiscovered:Boolean = false;
		private static var waitingForServicesDiscovered:Boolean = false;
		private static var discoveryTimeStamp:Number;
		private static var _activeBluetoothPeripheral:Peripheral;
		private static const MAX_SCAN_TIME_IN_SECONDS:int = 320;
		private static var discoverServiceOrCharacteristicTimer:Timer;//sometimes discover services just doesn't give anything, mainly with xdrip/xbridge this happened
		private static const DISCOVER_SERVICES_OR_CHARACTERISTICS_RETRY_TIME_IN_SECONDS:int = 1;
		private static const MAX_RETRY_DISCOVER_SERVICES_OR_CHARACTERISTICS:int = 5;
		private static var amountOfDiscoverServicesOrCharacteristicsAttempt:int = 0;
		private static var awaitingConnect:Boolean = false;
		private static var scanTimer:Timer;//only for peripheral types of type not always scan
		private static var reconnectTimer:Timer;	

		/**
		 * is the peripheral connected or not, not applicable to MiaoMiao which is handled by BackgroundFetch ANE 
		 */
		private static var peripheralConnected:Boolean = false;
		
		//Dexcom G5 variables
		private static var timeStampOfLastG5Reading:Number = 0;
		private static const G5_BATTERY_READ_PERIOD_MS:Number = 1000 * 60 * 60 * 12; // how often to poll battery data (12 hours)
		private static var authRequest:AuthRequestTxMessage = null;
		private static var authStatus:AuthStatusRxMessage = null;
		private static var awaitingAuthStatusRxMessage:Boolean = false;//used for G5, to detect situations where other app is connecting to G5
		private static var timeStampOfLastInfoAboutOtherApp:Number = 0;//used for G5, to detect situations where other app is connecting to G5
		/**
		 * If user has other app running that connects to the same G5 transmitter, this will not work<br>
		 * The app is trying to detect this situation, to avoid complaints<br>
		 * However the detection mechanism sometimes thinks there's another app trying to connect althought this is not the case<br>
		 * Therefore the amount of notifications will be reduced, this setting counts the number
		 */
		private static var MAX_WARNINGS_OTHER_APP_CONNECTING_TO_G5:int = 5;
		private static var G5_RECONNECT_TIME_IN_SECONDS:int = 15
				
		//Dexcom G4 variables
		private static var timeStampOfLastWarningUnknownG4Command:Number = 0;
		//list of packet types seen in logs for xdrips from xdripkit.co.uk
		private static var listOfSeenInvalidPacketTypes:Array = [49, 50, 51, 52, 53, 54, 55, 56, 57, 84];
		private static var unsupportedPacketType:int = 0;

		//Transmiter_PL variables
		private static var timeStampSinceLastSensorAgeUpdate_Transmiter_PL:Number = 0;
		private static var previousSensorAgeValue_Transmiter_PL:Number = 0;

		//Blucon variables
		private static var m_getNowGlucoseDataIndexCommand:Boolean = false;
		private static var m_currentTrendIndex:int;
		private static var m_currentBlockNumber:String = "";
		private static var m_currentOffset:int = 0;
		private static var m_minutesDiffToLastReading:int = 0;
		private static var m_minutesBack:int;
		private static var m_getOlderReading:Boolean = false;
		private static var m_getNowGlucoseDataCommand:Boolean = false;// to be sure we wait for a GlucoseData Block and not using another block
		private static var m_persistentTimeLastBg:Number;
		private static var m_blockNumber:int = 0;
		private static var m_full_data:ByteArray = new ByteArray();
		private static var nowGlucoseOffset:int = 0;
		private static var timeStampOfLastDeviceNotPairedForBlukon:Number = 0;
		private static var blukonCurrentCommand:String="";
		private static var GET_SENSOR_AGE_DELAY_IN_SECONDS:int =  3 * 3600;
		private static var FSLSensorAGe:Number;
		private static var startedMonitoringAndRangingBeaconsInRegion:Boolean = false;//only for Blucon
						
		//MiaoMiao variables
		public static var _amountOfConsecutiveSensorNotDetectedForMiaoMiao:int = 0;
		/**
		 * if miaomiao, this is the amount of times a sensorNotDetected was received consecutively without receiving a full data packet
		 */
		public static function get amountOfConsecutiveSensorNotDetectedForMiaoMiao():int
		{
			return _amountOfConsecutiveSensorNotDetectedForMiaoMiao;
		}
		
		private static function set activeBluetoothPeripheral(value:Peripheral):void
		{
			if (value == _activeBluetoothPeripheral)
				return;
			
			_activeBluetoothPeripheral = value;
			
			if (_activeBluetoothPeripheral != null) {
				_activeBluetoothPeripheral.addEventListener(PeripheralEvent.DISCOVER_SERVICES, peripheral_discoverServicesHandler );
				_activeBluetoothPeripheral.addEventListener(PeripheralEvent.DISCOVER_CHARACTERISTICS, peripheral_discoverCharacteristicsHandler );
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.UPDATE, peripheral_characteristic_updatedHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.UPDATE_ERROR, peripheral_characteristic_errorHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.SUBSCRIBE, peripheral_characteristic_subscribeHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.SUBSCRIBE_ERROR, peripheral_characteristic_subscribeErrorHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.UNSUBSCRIBE, peripheral_characteristic_unsubscribeHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.WRITE_SUCCESS, peripheral_characteristic_writeHandler);
				_activeBluetoothPeripheral.addEventListener(CharacteristicEvent.WRITE_ERROR, peripheral_characteristic_writeErrorHandler);
			}
		}
		
		private static function get activeBluetoothPeripheral():Peripheral {
			return _activeBluetoothPeripheral;
		}
		
		public function BluetoothService()
		{
			if (_instance != null) {
				throw new Error("BluetoothService class constructor can not be used");	
			}
		}
		
		/**
		 * start all bluetooth related activity : scanning, connecting, start listening ...<br>
		 * Also intializes BlueToothDevice with values retrieved from Database. 
		 */
		public static function init():void {
			if (!initialStart)
				return;
			else
				initialStart = false;
			
			peripheralConnected = false;
			
			CommonSettings.instance.addEventListener(SettingsServiceEvent.SETTING_CHANGED, commonSettingChanged);
			NotificationService.instance.addEventListener(NotificationServiceEvent.NOTIFICATION_EVENT, notificationReceived);
			NotificationService.instance.addEventListener(NotificationServiceEvent.NOTIFICATION_SELECTED_EVENT, notificationReceived);

			//blukon
			m_getNowGlucoseDataCommand = false;
			m_getNowGlucoseDataIndexCommand = false;
			m_getOlderReading = false;
			m_blockNumber = 0;
			
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "0");
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_BATTERY_LEVEL, "0");
			
			if (BlueToothDevice.isMiaoMiao()) {
				BackgroundFetch.startScanDeviceMiaoMiao();
				if (BlueToothDevice.known()) {
					BackgroundFetch.setMiaoMiaoMac(BlueToothDevice.address);
				}
			}
			
			setPeripheralUUIDs();
			
			BluetoothLE.init(DistriqtKey.distriqtKey);
			if (BluetoothLE.isSupported) {
				switch (BluetoothLE.service.authorisationStatus()) {
					case AuthorisationStatus.SHOULD_EXPLAIN:
						BluetoothLE.service.requestAuthorisation();
						break;
					case AuthorisationStatus.DENIED:
					case AuthorisationStatus.RESTRICTED:
					case AuthorisationStatus.UNKNOWN:
						break;
					
					case AuthorisationStatus.NOT_DETERMINED:
					case AuthorisationStatus.AUTHORISED:				
						if (BlueToothDevice.isMiaoMiao()) {
							addMiaoMiaoEventListeners();
						} else {
							addBluetoothLEEventListeners();
						}
						
						var blueToothServiceEvent:BlueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.BLUETOOTH_SERVICE_INITIATED);
						_instance.dispatchEvent(blueToothServiceEvent);
						
						switch (BluetoothLE.service.centralManager.state)
						{
							case BluetoothLEState.STATE_ON:	
								// We can use the Bluetooth LE functions
								bluetoothStatusIsOn();
								myTrace("in init, bluetooth is switched on")
								break;
							case BluetoothLEState.STATE_OFF:
								myTrace("in init, bluetooth is switched off")
								break;
							case BluetoothLEState.STATE_RESETTING:	
								break;
							case BluetoothLEState.STATE_UNAUTHORISED:
								break;
							case BluetoothLEState.STATE_UNSUPPORTED:
								break;
							case BluetoothLEState.STATE_UNKNOWN:
								break;
						}
				}
				
			} else {
				myTrace("Unfortunately your Device does not support Bluetooth Low Energy");
			}
		}
		
		private static function notificationReceived(event:NotificationServiceEvent):void {
			if (event != null) {
				var notificationEvent:NotificationEvent = event.data as NotificationEvent;
				if (notificationEvent.id == NotificationService.ID_FOR_OTHER_G5_APP) {
					AlertManager.showSimpleAlert
					(
						ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app"),
						ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app_info")
					);
				} else if (notificationEvent.id == NotificationService.ID_FOR_DEAD_OR_EXPIRED_SENSOR_TRANSMITTER_PL) {
					AlertManager.showSimpleAlert
						(
						ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"),
						ModelLocator.resourceManagerInstance.getString("bluetoothservice","dead_or_expired_sensor")
					);
				}
				else if (notificationEvent.id == NotificationService.ID_FOR_SENSOR_NOT_DETECTED_MIAOMIAO) {
					AlertManager.showSimpleAlert
					(
						ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"),
						ModelLocator.resourceManagerInstance.getString("bluetoothservice","sensor_not_detected_miaomiao")
					);
				} 
			}
		}
		
		private static function commonSettingChanged(event:SettingsServiceEvent):void {
			if (event.data == CommonSettings.COMMON_SETTING_PERIPHERAL_TYPE) {
				myTrace("in commonSettingChanged, event.data = COMMON_SETTING_PERIPHERAL_TYPE");
				
				//new peripheraltype, all bluetoothe uuid's need to get  new values
				setPeripheralUUIDs();
				
				if (scanTimer != null) {
					if (scanTimer.running) {
						scanTimer.stop();
					}
					scanTimer = null;
				}
				
				stopScanning(null);//need to stop scanning because device type has changed, means also the UUID to scan for
				if (!BlueToothDevice.isFollower()) {
					if (BlueToothDevice.alwaysScan() && BlueToothDevice.transmitterIdKnown()) {
						if (BluetoothLE.service.centralManager.state == BluetoothLEState.STATE_ON) {
							startScanning();
						}
					} else {
					}
				}
				
				BlueToothDevice.forgetBlueToothDevice();
				
				if (BlueToothDevice.isMiaoMiao()) {
					BackgroundFetch.startScanDeviceMiaoMiao();
					removeBluetoothLEEventListeners();
					addMiaoMiaoEventListeners();
				} else {
					BackgroundFetch.stopScanDeviceMiaoMiao();
					addBluetoothLEEventListeners();
					removeMiaoMiaoEventListeners();
				}
			} else if (event.data == CommonSettings.COMMON_SETTING_TRANSMITTER_ID) {
				myTrace("in commonSettingChanged, event.data = COMMON_SETTING_TRANSMITTER_ID, calling BlueToothDevice.forgetbluetoothdevice");
				BlueToothDevice.forgetBlueToothDevice();
				if (BlueToothDevice.transmitterIdKnown() && BlueToothDevice.alwaysScan()) {
					if (BluetoothLE.service.centralManager.state == BluetoothLEState.STATE_ON) {
						myTrace("in commonSettingChanged, event.data = COMMON_SETTING_TRANSMITTER_ID, restart scanning");
						startScanning();
					} else {
						myTrace("in commonSettingChanged, event.data = COMMON_SETTING_TRANSMITTER_ID, restart scanning needed but bluetooth is not on");
					}
				} else {
					myTrace("in commonSettingChanged, event.data = COMMON_SETTING_TRANSMITTER_ID but transmitter id not known or alwaysscan is false");
				}
			} else if (event.data == CommonSettings.COMMON_SETTING_CURRENT_SENSOR) {
				if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CURRENT_SENSOR) == "0") {
					myTrace("in commonSettingChanged, setting timeStampSinceLastSensorAgeUpdate_Transmiter_PL and previousSensorAgeValue_Transmiter_PL to 0");
					timeStampSinceLastSensorAgeUpdate_Transmiter_PL = 0;
					previousSensorAgeValue_Transmiter_PL = 0;
				}
			}
		}
		
		private static function bluetoothStateChangedHandler(event:BluetoothLEEvent):void
		{
			switch (BluetoothLE.service.centralManager.state)
			{
				case BluetoothLEState.STATE_ON:	
					myTrace("in bluetoothStateChangedHandler, bluetooth is switched on")
					// We can use the Bluetooth LE functions
					bluetoothStatusIsOn();
					break;
				case BluetoothLEState.STATE_OFF:
					myTrace("in bluetoothStateChangedHandler, bluetooth is switched off")
					break;//does the device automatically change to connected ? 
				case BluetoothLEState.STATE_RESETTING:	
					break;
				case BluetoothLEState.STATE_UNAUTHORISED:	
					break;
				case BluetoothLEState.STATE_UNSUPPORTED:	
					break;
				case BluetoothLEState.STATE_UNKNOWN:
					break;
			}
		}
		
		private static function bluetoothStatusIsOn():void {
			if (activeBluetoothPeripheral != null && !(BlueToothDevice.alwaysScan())) {//do we ever pass here, activebluetoothperipheral is set to null after disconnect
				awaitingConnect = true;
				connectionAttemptTimeStamp = (new Date()).valueOf();
				BluetoothLE.service.centralManager.connect(activeBluetoothPeripheral);
				myTrace("in bluetoothStatusIsOn, Trying to connect to known device.");
			} else if (activeBluetoothPeripheral != null && (BlueToothDevice.isBlueReader() || BlueToothDevice.isDexcomG5() || BlueToothDevice.isBluKon())) {
				awaitingConnect = true;
				connectionAttemptTimeStamp = (new Date()).valueOf();
				BluetoothLE.service.centralManager.connect(activeBluetoothPeripheral);
				myTrace("in bluetoothStatusIsOn, Trying to connect.");
			} else if (BlueToothDevice.isMiaoMiao()) {
				if (BlueToothDevice.known()) {
					myTrace("in bluetoothStatusIsOn, isMiaoMiao");
					BackgroundFetch.setMiaoMiaoMac(BlueToothDevice.address);
					startScanning();
				}
				myTrace("in bluetoothStatusIsOn, device is miaomiao - DO WE NEED TO DEVELOP ANYTHING HERE ?.");
			} else if (BlueToothDevice.known() || (BlueToothDevice.alwaysScan() && BlueToothDevice.transmitterIdKnown())) {
				myTrace("bluetoothStatusIsOn, call startScanning");
				startScanning();
			} else {
				myTrace("in bluetootbluetoothStatusIsOn; but not restarting scan");
			}
		}
		
		public static function startScanning(itsNotAnAlwaysScanDevice:Boolean = false):void {
			if (BlueToothDevice.isFollower()) {
				myTrace("in startScanning but follower, not starting scan");
				return;
			}
			
			if (BlueToothDevice.isMiaoMiao()) {
				myTrace("in startScanning, is miaomiao");
				BackgroundFetch.startScanningForMiaoMiao();
				return;
			}

			if (!BluetoothLE.service.centralManager.isScanning) {
				if (!BluetoothLE.service.centralManager.scanForPeripherals(advertisement_UUID_Vector))
				{
					myTrace("in startScanning, failed to start scanning for peripherals");
					return;
				} else {
					myTrace("in startScanning, started scanning for peripherals");
					if (itsNotAnAlwaysScanDevice) {
						myTrace("in startScanning, it's a device which does not require always scanning, start the scan timer");
						scanTimer = new Timer(MAX_SCAN_TIME_IN_SECONDS * 1000, 1);
						scanTimer.addEventListener(TimerEvent.TIMER, stopScanning);
						scanTimer.start();
					}
					if (BlueToothDevice.isBluKon()) {
						startMonitoringAndRangingBeaconsInRegion(Blucon_Advertisement_UUID);
					}
				}
			} else {
				myTrace("in startscanning but already scanning");
			}
		}
		
		public static function stopScanning(event:flash.events.Event):void {
			myTrace("in stopScanning");
			if (BlueToothDevice.isMiaoMiao()) {
				BackgroundFetch.stopScanningMiaoMiao();				
			} else {
				if (BluetoothLE.service.centralManager.isScanning) {
					myTrace("in stopScanning, is scanning, call stopScan");
					BluetoothLE.service.centralManager.stopScan();
					if (BlueToothDevice.isBluKon()) {
						stopMonitoringAndRangingBeaconsInRegion(Blucon_Advertisement_UUID);
					}
					_instance.dispatchEvent(new BlueToothServiceEvent(BlueToothServiceEvent.STOPPED_SCANNING));
				}
			}
		}
		
		private static function central_peripheralDiscoveredHandler(event:PeripheralEvent):void {
			myTrace("in central_peripheralDiscoveredHandler, stop scanning. Device name = " + event.peripheral.name + ", Device address = " + event.peripheral.uuid);
			BluetoothLE.service.centralManager.stopScan();
			if (BlueToothDevice.isBluKon()) {
				stopMonitoringAndRangingBeaconsInRegion(Blucon_Advertisement_UUID);
			}

			discoveryTimeStamp = (new Date()).valueOf();
			if (awaitingConnect && !(BlueToothDevice.alwaysScan())) {
				myTrace("in central_peripheralDiscoveredHandler, but already awaiting connect, restart scan");
				startRescan(null);
				return;
			}
			
			if (BlueToothDevice.isDexcomG5()) {
				if ((new Date()).valueOf() - timeStampOfLastG5Reading < 60 * 1000) {
					myTrace("in central_peripheralDiscoveredHandler, G5 but last reading was less than 1 minute ago, ignoring this peripheral discovery. restart scan");
					startRescan(null);
					return;
				}
			}
			
			if (BlueToothDevice.isBluKon()) {
				if (peripheralConnected) {
					myTrace("in central_peripheralDiscoveredHandler, blukon, already connected. Ignoring this device (it could be another one) and not restarting scanning");
					return;
				}
			}
			
			//event.peripheral contains a Peripheral object with information about the Peripheral
			//only for DexcomG5 and Blucon we look at the device name. For the others we don't care about the device name
			var expectedPeripheralName:String;
			if (BlueToothDevice.isDexcomG5()) {
				expectedPeripheralName = "DEXCOM" + CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TRANSMITTER_ID).substring(4,6);
				myTrace("in central_peripheralDiscoveredHandler, expected g5 peripheral name = " + expectedPeripheralName);
			} else if (BlueToothDevice.isBluKon()) {
				expectedPeripheralName = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TRANSMITTER_ID).toUpperCase();
				if (expectedPeripheralName.toUpperCase().indexOf("BLU") < 0) {
					while (expectedPeripheralName.length < 5) {
						expectedPeripheralName = "0" + expectedPeripheralName;
					}
					expectedPeripheralName = "BLU" + expectedPeripheralName;
				}
				myTrace("in central_peripheralDiscoveredHandler, expected blukon peripheral name = " + expectedPeripheralName);
			}
			
			if (
				!(BlueToothDevice.alwaysScan()) //if always scan peripheral, we don't look at the name of the peripheral
				||
				(BlueToothDevice.isDexcomG5() &&
					(
						(event.peripheral.name as String).toUpperCase().indexOf(expectedPeripheralName) > -1
					)
				)
				||
				(BlueToothDevice.isBluKon() &&
					(
						(event.peripheral.name as String).toUpperCase().indexOf(expectedPeripheralName) > -1
					)
				)
			) {
				if (BlueToothDevice.address != "") {
					if (BlueToothDevice.address != event.peripheral.uuid) {
						myTrace("in central_peripheralDiscoveredHandler, UUID of found peripheral does not match with name of the UUID stored in the database - will ignore this peripheral.");
						startRescan(null);
						return;
					}
				} else {
					//we store also this peripheral, as of now, all future connect attempts will be only to this one, until the user choses "forget device"
					BlueToothDevice.address = event.peripheral.uuid;
					BlueToothDevice.name = event.peripheral.name;
					myTrace("in central_peripheralDiscoveredHandler, Device details will be stored in database. Future attempts will only use this device to connect to.");
				}
				myTrace("in central_peripheralDiscoveredHandler, try to connect");
				awaitingConnect = true;
				connectionAttemptTimeStamp = (new Date()).valueOf();
				BluetoothLE.service.centralManager.connect(event.peripheral);
			} else {
				myTrace("in central_peripheralDiscoveredHandler, doesn't seem to be a device we are interested in. Restart scan");
				startRescan(null);
			}
		}
		
		private static function central_peripheralConnectHandler(event:PeripheralEvent):void {
			myTrace("in central_peripheralConnectHandler");
			peripheralConnected = true;
			
			blukonCurrentCommand = "";
			
			if (BlueToothDevice.isBluKon()) {
				if (BluetoothLE.service.centralManager.isScanning) {
					//this may happen because for blukon, after disconnect, we start scanning and also try to reconnect
					myTrace("in central_peripheralConnectHandler, blukon and scanning. Stop scanning");
					BluetoothLE.service.centralManager.stopScan();
					if (BlueToothDevice.isBluKon()) {
						stopMonitoringAndRangingBeaconsInRegion(Blucon_Advertisement_UUID);
					}
				}
			}
			
			if (BlueToothDevice.isDexcomG5()) {
				if ((new Date()).valueOf() - timeStampOfLastG5Reading < 60 * 1000) {
					myTrace("in central_peripheralConnectHandler, G5 but last reading was less than 1 minute ago, disconnecting");
					if (!BluetoothLE.service.centralManager.disconnect(activeBluetoothPeripheral)) {
						myTrace("in central_peripheralConnectHandler, disconnect failed");
					}
					return;
				}
			}
			
			if (scanTimer != null) {
				if (scanTimer.running) {
					myTrace("in central_peripheralConnectHandler, stopping scanTimer");
					scanTimer.stop();
				}
				scanTimer = null;
			}

			if (!awaitingConnect && !BlueToothDevice.isBluKon()) {
				myTrace("in central_peripheralConnectHandler but awaitingConnect = false, will disconnect");
				BluetoothLE.service.centralManager.disconnect(event.peripheral);
				return;
			} 
			
			awaitingConnect = false;
			if (!BlueToothDevice.alwaysScan() && !BlueToothDevice.isMiaoMiao()) {//should never be miaomiao ?
				if ((new Date()).valueOf() - connectionAttemptTimeStamp > maxTimeBetweenConnectAttemptAndConnectSuccess * 1000) { //not waiting more than 3 seconds between device discovery and connection success
					myTrace("in central_peripheralConnectHandler but time between connect attempt and connect success is more than " + maxTimeBetweenConnectAttemptAndConnectSuccess + " seconds. Will disconnect");
					BluetoothLE.service.centralManager.disconnect(event.peripheral);
					return;
				} 
			}
			
			if (BlueToothDevice.isBlueReader() || BlueToothDevice.isBluKon()) {
				_instance.dispatchEvent(new BlueToothServiceEvent(BlueToothServiceEvent.BLUETOOTH_DEVICE_CONNECTION_COMPLETED));
			}
			
			myTrace("in central_peripheralConnectHandler, connected to peripheral");
			if (activeBluetoothPeripheral == null)
				activeBluetoothPeripheral = event.peripheral;
			
			if (BlueToothDevice.isBluKon() || BlueToothDevice.isBlueReader() || BlueToothDevice.isDexcomG5())
				activeBluetoothPeripheral = event.peripheral;

			discoverServices();
		}
		
		private static function discoverServices(event:flash.events.Event = null):void {
			myTrace("in discoverServices");
			waitingForServicesDiscovered = false;
			if (activeBluetoothPeripheral == null)//rare case, user might have done forget xdrip while waiting for reattempt
				return;
			
			if (discoverServiceOrCharacteristicTimer != null) {
				discoverServiceOrCharacteristicTimer.stop();
				discoverServiceOrCharacteristicTimer = null;
			}
			
			if (!peripheralConnected) {
				myTrace("in discoverservices,  but peripheralConnected = false, returning");
				amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
				return;
			}
			
			if (amountOfDiscoverServicesOrCharacteristicsAttempt < MAX_RETRY_DISCOVER_SERVICES_OR_CHARACTERISTICS) {
				amountOfDiscoverServicesOrCharacteristicsAttempt++;
				myTrace("in discoverservices, attempt " + amountOfDiscoverServicesOrCharacteristicsAttempt);
				
				waitingForServicesDiscovered = true;
				activeBluetoothPeripheral.discoverServices(service_UUID_Vector);
				if (!BlueToothDevice.isBluKon()) {
					discoverServiceOrCharacteristicTimer = new Timer(DISCOVER_SERVICES_OR_CHARACTERISTICS_RETRY_TIME_IN_SECONDS * 1000, 1);
					discoverServiceOrCharacteristicTimer.addEventListener(TimerEvent.TIMER, discoverServices);
					discoverServiceOrCharacteristicTimer.start();
				}
			} else {
				myTrace("in discoverServices, Maximum amount of attempts for discover bluetooth services reached.")
				amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
				
				//i just happens that retrying doesn't help anymore
				//so disconnecting and rescanning seems the only solution ?
				
				//disconnect will cause central_peripheralDisconnectHandler to be called (although not sure because setting activeBluetoothPeripheral to null, i would expect that removes also the eventlisteners
				//central_peripheralDisconnectHandler will see that activeBluetoothPeripheral == null and so 
				var temp:Peripheral = activeBluetoothPeripheral;
				activeBluetoothPeripheral = null;
				BluetoothLE.service.centralManager.disconnect(temp);
				
				myTrace("in discoverServices, will_re_scan_for_device");
				if ((BluetoothLE.service.centralManager.state == BluetoothLEState.STATE_ON)) {
					bluetoothStatusIsOn();
				}
			}
		}
		
		private static function central_peripheralDisconnectHandler(event:flash.events.Event = null):void {
			myTrace('in central_peripheralDisconnectHandler');
			if (BlueToothDevice.isDexcomG5()) {
				amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
			}
			if (BlueToothDevice.isDexcomG5() && awaitingAuthStatusRxMessage) {
				myTrace('in central_peripheralDisconnectHandler, Dexcom G5 and awaitingAuthStatusRxMessage, seems another app is trying to connecto to the G5');
				awaitingAuthStatusRxMessage = false;
				if (new Number(LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP)) < MAX_WARNINGS_OTHER_APP_CONNECTING_TO_G5) {
					if ((new Date()).valueOf() - timeStampOfLastInfoAboutOtherApp > 1 * 3600 * 1000) {//not repeating the warning every 5 minutes, only once per hour
						myTrace('in central_peripheralDisconnectHandler, giving warning to the user');
						timeStampOfLastInfoAboutOtherApp = (new Date()).valueOf();
						if (BackgroundFetch.appIsInForeground()) {
							AlertManager.showSimpleAlert
								(
									ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app"),
									ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app_info")
								);
							BackgroundFetch.vibrate();
						} else {
							var notificationBuilderG5OtherAppRunningInfo:NotificationBuilder = new NotificationBuilder()
								.setCount(BadgeBuilder.getAppBadge())
								.setId(NotificationService.ID_FOR_OTHER_G5_APP)
								.setAlert(ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app"))
								.setTitle(ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app"))
								.setBody(ModelLocator.resourceManagerInstance.getString("bluetoothservice","other_G5_app_info"))
								.enableVibration(true)
							Notifications.service.notify(notificationBuilderG5OtherAppRunningInfo.build());
						}
						LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP, (new Number(LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP)) + 1).toString());
						myTrace("in central_peripheralDisconnectHandler, increased LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP, new value = " + LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP));
					}
				} else {
					myTrace("in central_peripheralDisconnectHandler, maximum number of other app warnings reached, value = " + LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_AMOUNT_OF_WARNINGS_OTHER_APP));
				}
			}
			
			if (BlueToothDevice.isBluKon()) {
				peripheralConnected = false;
				awaitingConnect = false;
				//try to reconnect and also restart scanning, to cover reconnect issue. Because maybe the transmitter starts re-advertising
				tryReconnect();
				startScanning();
			} else if (BlueToothDevice.isBlueReader()) {
				peripheralConnected = false;
				awaitingConnect = false;
				tryReconnect();
			} else if (BlueToothDevice.isDexcomG5()) {
				startReconnectTimer(G5_RECONNECT_TIME_IN_SECONDS);
			} else {
				peripheralConnected = false;
				awaitingConnect = false;
				forgetActiveBluetoothPeripheral();
				startRescan(null);
			}
		}
		
		private static function startReconnectTimer(timerInSeconds:int):void {
			myTrace("in startReconnectTime with timer =" + timerInSeconds);
			reconnectTimer = new Timer(timerInSeconds * 1000, 1);
			reconnectTimer.addEventListener(TimerEvent.TIMER, tryReconnect);
			reconnectTimer.start();
		}
		
		private static function tryReconnect(event:flash.events.Event = null):void {
			if ((BluetoothLE.service.centralManager.state == BluetoothLEState.STATE_ON)) {
				bluetoothStatusIsOn();
			} else {
				//no need to further retry, a reconnect will be done as soon as bluetooth is switched on
			}
		}
		
		private static function peripheral_discoverServicesHandler(event:PeripheralEvent):void {
			if (!waitingForServicesDiscovered && !(BlueToothDevice.alwaysScan())) {
				myTrace("in peripheral_discoverServicesHandler but not waitingForServicesDiscovered and not alwaysscan device, ignoring");
				return;
			}
			myTrace("in peripheral_discoverServicesHandler");
			waitingForServicesDiscovered = false;
			
			if (discoverServiceOrCharacteristicTimer != null) {
				discoverServiceOrCharacteristicTimer.stop();
				discoverServiceOrCharacteristicTimer = null;
			}
			amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
			
			if (BlueToothDevice.isDexcomG5()) {
				awaitingAuthStatusRxMessage = false;	
			}
			
			if (event.peripheral.services.length > 0) {
				myTrace("in peripheral_discoverServicesHandler, call discoverCharacteristics");
				discoverCharacteristics();
			} else {
				myTrace("in peripheral_discoverServicesHandler, event.peripheral.services.length == 0, not calling discoverCharacteristics");
			}
		}
		
		private static function discoverCharacteristics(event:flash.events.Event = null):void {
			if (activeBluetoothPeripheral == null)//rare case, user might have done forget xdrip while waiting to reattempt
				return;
			
			if (discoverServiceOrCharacteristicTimer != null) {
				discoverServiceOrCharacteristicTimer.stop();
				discoverServiceOrCharacteristicTimer = null;
			}
			
			if (!peripheralConnected) {
				myTrace("in discoverCharacteristics, but peripheralConnected = false, returning");
				amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
				return;
			}
			
			if (amountOfDiscoverServicesOrCharacteristicsAttempt < MAX_RETRY_DISCOVER_SERVICES_OR_CHARACTERISTICS
				&&
				activeBluetoothPeripheral.services.length > 0) {
				amountOfDiscoverServicesOrCharacteristicsAttempt++;
				myTrace('in discoverCharacteristics, launching_discovercharacteristics_attempt_amount' + " " + amountOfDiscoverServicesOrCharacteristicsAttempt);
				
				var index:int;
				var o:Object;
				for each (o in activeBluetoothPeripheral.services) {
					if (service_UUID.indexOf((o.uuid as String).toUpperCase()) > -1) {
						break;
					}
					index++;
				}
				waitingForPeripheralCharacteristicsDiscovered = true;
				activeBluetoothPeripheral.discoverCharacteristics(activeBluetoothPeripheral.services[index], characteristics_UUID_Vector);
				discoverServiceOrCharacteristicTimer = new Timer(DISCOVER_SERVICES_OR_CHARACTERISTICS_RETRY_TIME_IN_SECONDS * 1000, 1);
				discoverServiceOrCharacteristicTimer.addEventListener(TimerEvent.TIMER, discoverCharacteristics);
				discoverServiceOrCharacteristicTimer.start();
			} else {
				myTrace('in discoverCharacteristics, call tryReconnect');
				tryReconnect();
			}
		}
		
		private static function peripheral_discoverCharacteristicsHandler(event:PeripheralEvent):void {
			myTrace("in peripheral_discoverCharacteristicsHandler");
			if (!waitingForPeripheralCharacteristicsDiscovered && !BlueToothDevice.isBluKon()) {
				myTrace("in peripheral_discoverCharacteristicsHandler but not waitingForPeripheralCharacteristicsDiscovered");
				return;
			}
			waitingForPeripheralCharacteristicsDiscovered = false;
			if (discoverServiceOrCharacteristicTimer != null) {
				discoverServiceOrCharacteristicTimer.stop();
				discoverServiceOrCharacteristicTimer = null;
			}
			myTrace("Bluetooth peripheral characteristics discovered");
			amountOfDiscoverServicesOrCharacteristicsAttempt = 0;
			
			//used to loop through services
			var servicesIndex:int = 0;
			
			//used to loop through characteristics
			var Read_CharacteristicsIndex:int = 0;
			var Write_CharacteristicsIndex:int = 0;
			
			//only needed for G5
			awaitingAuthStatusRxMessage = false;
			
			var o:Object;
			
			for each (o in activeBluetoothPeripheral.services) {
				if (service_UUID.indexOf((o.uuid as String).toUpperCase()) > -1) {
					break;
				}
				servicesIndex++;
			}
			for each (o in activeBluetoothPeripheral.services[servicesIndex].characteristics) {
				if (RX_Characteristic_UUID.indexOf((o.uuid as String).toUpperCase()) > -1) {
					break;
				}
				Read_CharacteristicsIndex++;
			}
			for each (o in activeBluetoothPeripheral.services[servicesIndex].characteristics) {
				if (TX_Characteristic_UUID.indexOf((o.uuid as String).toUpperCase()) > -1) {
					break;
				}
				Write_CharacteristicsIndex++;
			}
			readCharacteristic = event.peripheral.services[servicesIndex].characteristics[Read_CharacteristicsIndex];
			writeCharacteristic = event.peripheral.services[servicesIndex].characteristics[Write_CharacteristicsIndex];
			myTrace("subscribing to ReadCharacteristic");
			
			if (!activeBluetoothPeripheral.subscribeToCharacteristic(readCharacteristic))
			{
				myTrace("Subscribe to characteristic failed due to invalid adapter state.");
			}
		}
		
		public static function writeToCharacteristic(value:ByteArray):void {
			if (!activeBluetoothPeripheral.writeValueForCharacteristic(writeCharacteristic, value)) {
				myTrace("ackG4CharacteristicUpdate writeValueForCharacteristic failed");
			}
		}
		
		private static function peripheral_characteristic_updatedHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_updatedHandler characteristic uuid = " + getCharacteristicName(event.characteristic.uuid) +
				" with byte 0 = " + event.characteristic.value[0] + " decimal.");
			
			var blueToothServiceEvent:BlueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.CHARACTERISTIC_UPDATE);
			_instance.dispatchEvent(blueToothServiceEvent);
			
			//now start reading the values
			var value:ByteArray = event.characteristic.value;
			var packetlength:int = value.readUnsignedByte();
			if (packetlength == 0) {
				myTrace("in peripheral_characteristic_updatedHandler, data packet received from transmitter with length 0, no further processing");
			} else {
				value.position = 0;
				value.endian = Endian.LITTLE_ENDIAN;
				myTrace("in peripheral_characteristic_updatedHandler, data packet received from transmitter : " + utils.UniqueId.bytesToHex(value));
				value.position = 0;
				if (BlueToothDevice.isDexcomG5()) {
					processG5TransmitterData(value, event.characteristic);
				} else if (BlueToothDevice.isBluKon()) {
					processBLUKONTransmitterData(value);
				} else if (BlueToothDevice.isDexcomG4() || BlueToothDevice.isxBridgeR()) {
					processG4TransmitterData(value);
				} else if (BlueToothDevice.isBlueReader()) {
					processBlueReaderTransmitterData(value);
				} else if (BlueToothDevice.isTransmiter_PL()) {
					processTRANSMITER_PLTransmitterData(value);
				} else {
					myTrace("in peripheral_characteristic_updatedHandler, device type not known");
				}
			}
		}
		
		private static function peripheral_characteristic_writeHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_writeHandler " + getCharacteristicName(event.characteristic.uuid));
			if (BlueToothDevice.isDexcomG4() || BlueToothDevice.isxBridgeR()) {
				_instance.dispatchEvent(new BlueToothServiceEvent(BlueToothServiceEvent.BLUETOOTH_DEVICE_CONNECTION_COMPLETED));
			} else if (BlueToothDevice.isDexcomG5() && event.characteristic.uuid.toUpperCase() == G5_Authentication_Characteristic_UUID.toUpperCase()) {
				awaitingAuthStatusRxMessage = true;
			}
		}
		
		private static function peripheral_characteristic_writeErrorHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_writeErrorHandler"  + getCharacteristicName(event.characteristic.uuid));
			if (event.error != null)
				myTrace("event.error = " + event.error);
			myTrace("event.errorCode = " + event.errorCode); 
		}
		
		private static function peripheral_characteristic_errorHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_errorHandler"  + getCharacteristicName(event.characteristic.uuid));
		}
		
		private static function peripheral_characteristic_subscribeHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_subscribeHandler success: " + getCharacteristicName(event.characteristic.uuid));
			if (BlueToothDevice.isDexcomG5()) {
				if (event.characteristic.uuid.toUpperCase() == G5_Control_Characteristic_UUID.toUpperCase()) {
					getSensorData();
				} else {
					fullAuthenticateG5();
				}
			}
			if (!BlueToothDevice.alwaysScan()) {
				_instance.dispatchEvent(new BlueToothServiceEvent(BlueToothServiceEvent.BLUETOOTH_DEVICE_CONNECTION_COMPLETED));
			}
		}
		
		private static function peripheral_characteristic_subscribeErrorHandler(event:CharacteristicEvent):void {
			myTrace("in peripheral_characteristic_subscribeErrorHandler: " + getCharacteristicName(event.characteristic.uuid));
			myTrace("in peripheral_characteristic_subscribeErrorHandler, event.error = " + event.error);
			myTrace("in peripheral_characteristic_subscribeErrorHandler, event.errorcode  = " + event.errorCode);
			if ((new Date()).valueOf() - timeStampOfLastDeviceNotPairedForBlukon > 4.75 * 60 * 1000) {
				if (BlueToothDevice.isBluKon()) {
					if (event.characteristic.uuid.toUpperCase() == Blucon_RX_Characteristic_UUID.toUpperCase()
						&&
						event.errorCode == 15 
					) {
						myTrace("in peripheral_characteristic_subscribeErrorHandler, blukon not paired, dispatching DEVICE_NOT_PAIRED event");
						var blueToothServiceEvent:BlueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.DEVICE_NOT_PAIRED);
						_instance.dispatchEvent(blueToothServiceEvent);
						timeStampOfLastDeviceNotPairedForBlukon = (new Date()).valueOf();
					}
				}
			}
		}
		
		private static function peripheral_characteristic_unsubscribeHandler(event:CharacteristicEvent):void {
			myTrace("peripheral_characteristic_unsubscribeHandler: " + event.characteristic.uuid);	
		}
		
		/**
		 * Disconnects the active bluetooth peripheral if any and sets it to null (otherwise returns without doing anything)<br>
		 * address only for miaomiao because the cancelMiaoMiaoConnection method needs that mac, otherwise it will not forget the device
		 */
		public static function forgetActiveBluetoothPeripheral(address:String = ""):void {
			if (BlueToothDevice.isMiaoMiao()) {
				myTrace("in forgetActiveBluetoothPeripheral  miaomiao device");
				BackgroundFetch.cancelMiaoMiaoConnection(address);
				BackgroundFetch.resetMiaoMiaoMac();
				BackgroundFetch.forgetMiaoMiaoPeripheral();
			} else {
				myTrace("in forgetActiveBluetoothPeripheral");
				writeCharacteristic = null;
				readCharacteristic = null;
				if (activeBluetoothPeripheral == null)
					return;
				
				BluetoothLE.service.centralManager.disconnect(activeBluetoothPeripheral);
				activeBluetoothPeripheral = null;
				myTrace("bluetooth device forgotten");
			}
		}
		
		/**
		 * encode transmitter id as explained in xBridge2.pdf 
		 */
		public static function encodeTxID(TxID:String):Number {
			var returnValue:Number = 0;
			var tmpSrc:String = TxID.toUpperCase();
			returnValue |= getSrcValue(tmpSrc.charAt(0)) << 20;
			returnValue |= getSrcValue(tmpSrc.charAt(1)) << 15;
			returnValue |= getSrcValue(tmpSrc.charAt(2)) << 10;
			returnValue |= getSrcValue(tmpSrc.charAt(3)) << 5;
			returnValue |= getSrcValue(tmpSrc.charAt(4));
			return returnValue;
		}
		
		private static function decodeTxID(TxID:Number):String {
			var returnValue:String = "";
			returnValue += srcNameTable[(TxID >> 20) & 0x1F];
			returnValue += srcNameTable[(TxID >> 15) & 0x1F];
			returnValue += srcNameTable[(TxID >> 10) & 0x1F];
			returnValue += srcNameTable[(TxID >> 5) & 0x1F];
			returnValue += srcNameTable[(TxID >> 0) & 0x1F];
			return returnValue;
		}
		
		private static function getSrcValue(ch:String):int {
			var i:int = 0;
			for (i = 0; i < srcNameTable.length; i++) {
				if (srcNameTable[i] == ch) break;
			}
			return i;
		}
		
		private static function processG5TransmitterData(buffer:ByteArray, characteristic:Characteristic):void {
			myTrace("in processG5TransmitterData");
			awaitingAuthStatusRxMessage = false;
			buffer.endian = Endian.LITTLE_ENDIAN;
			var code:int = buffer.readByte();
			switch (code) {
				case 5:
					var blueToothServiceEvent:BlueToothServiceEvent;
					authStatus = new AuthStatusRxMessage(buffer);
					myTrace("in processG5TransmitterData, AuthStatusRxMessage created = " + UniqueId.byteArrayToString(authStatus.byteSequence));
					if (!authStatus.bonded) {
						myTrace("in processG5TransmitterData, not paired, dispatching DEVICE_NOT_PAIRED event");
						blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.DEVICE_NOT_PAIRED);
						_instance.dispatchEvent(blueToothServiceEvent);
					}
					
					//probably doesn't make sense to subscribe to characteristic ? because not paired yet
					myTrace("in processG5TransmitterData, Subscribing to WriteCharacteristic");
					if (!activeBluetoothPeripheral.subscribeToCharacteristic(writeCharacteristic))
					{
						myTrace("in processG5TransmitterData, Subscribe to characteristic failed due to invalid adapter state.");
					}
					break;
				case 3:
					buffer.position = 0;
					var authChallenge:AuthChallengeRxMessage = new AuthChallengeRxMessage(buffer);
					if (authRequest == null) {
						authRequest = new AuthRequestTxMessage(getTokenSize());
					}
					var key:ByteArray = cryptKey();
					var challengeHash:ByteArray = calculateHash(authChallenge.challenge);
					if (challengeHash != null) {
						var authChallengeTx:AuthChallengeTxMessage = new AuthChallengeTxMessage(challengeHash);
						if (!activeBluetoothPeripheral.writeValueForCharacteristic(characteristic, authChallengeTx.byteSequence)) {
							myTrace("in processG5TransmitterData case 3 writeValueForCharacteristic failed");
						}
					} else {
						myTrace("in processG5TransmitterData, challengehash == null");
					}
					break;
				case 47:
					var sensorRx:SensorRxMessage = new SensorRxMessage(buffer);
					
					if ((new Date()).valueOf() - new Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_G5_BATTERY_FROM_MARKER)) > BluetoothService.G5_BATTERY_READ_PERIOD_MS) {
						doBatteryInfoRequestMessage(characteristic);
					} else {
						doDisconnectMessageG5(characteristic);
					}
					
					//SPIKE: Save Sensor RX Timestmp for transmitter runtime display
					if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_G5_SENSOR_RX_TIMESTAMP) != String(sensorRx.timestamp))
						CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_SENSOR_RX_TIMESTAMP, String(sensorRx.timestamp));
					
					timeStampOfLastG5Reading = (new Date()).valueOf();
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
					blueToothServiceEvent.data = new TransmitterDataG5Packet(sensorRx.unfiltered, sensorRx.filtered, sensorRx.timestamp, sensorRx.transmitterStatus);
					_instance.dispatchEvent(blueToothServiceEvent);
					break;
				case 35:
					buffer.position = 0;
					if (!setStoredBatteryBytesG5(buffer)) {
						myTrace("in processG5TransmitterData , Could not save out battery data!");
					}
					doDisconnectMessageG5(characteristic);
					break;
				case 75:
					doDisconnectMessageG5(characteristic);
					break;
				default:
					myTrace("in processG5TransmitterData unknown code received : " + code);
					break;
			}
		}
		
		public static function setStoredBatteryBytesG5(data:ByteArray):Boolean {
			if (data.length < 10) {
				myTrace("in setStoredBatteryBytesG5, Store: BatteryRX dbg, data.length < 10, no further processing");
				return false;
			}
			var batteryInfoRxMessage:BatteryInfoRxMessage = new BatteryInfoRxMessage(data);
			myTrace("in setStoredBatteryBytesG5, Saving battery data: " + batteryInfoRxMessage.toString());
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_BATTERY_MARKER, UniqueId.bytesToHex(data));
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_RESIST, new Number(batteryInfoRxMessage.resist).toString());
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_RUNTIME, new Number(batteryInfoRxMessage.runtime).toString());
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_TEMPERATURE, new Number(batteryInfoRxMessage.temperature).toString());
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_VOLTAGEA, new Number(batteryInfoRxMessage.voltagea).toString());
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_G5_VOLTAGEB, new Number(batteryInfoRxMessage.voltageb).toString());
			return true;
		}
		
		private static function doDisconnectMessageG5(characteristic:Characteristic):void {
			myTrace("in doDisconnectMessageG5");
			if (activeBluetoothPeripheral != null) {
				if (!BluetoothLE.service.centralManager.disconnect(activeBluetoothPeripheral)) {
					myTrace("in doDisconnectMessageG5, failed");
				}
			}
			myTrace("in doDisconnectMessageG5, finished");
		}
		
		private static function doBatteryInfoRequestMessage(characteristic:Characteristic):void {
			myTrace("in doBatteryInfoRequestMessage");
			var batteryInfoTxMessage:BatteryInfoTxMessage =  new BatteryInfoTxMessage();
			if (!activeBluetoothPeripheral.writeValueForCharacteristic(characteristic, batteryInfoTxMessage.byteSequence)) {
				myTrace("in doBatteryInfoRequestMessage writeValueForCharacteristic failed");
			}
		}
		
		public static function calculateHash(data:ByteArray):ByteArray {
			if (data.length != 8) {
				myTrace("in calculateHash, Data length should be exactly 8.");
				return null;
			}
			var key:ByteArray = cryptKey();
			if (key == null)
				return null;
			var doubleData:ByteArray = new ByteArray();
			doubleData.writeBytes(data);
			doubleData.writeBytes(data);
			var aesBytes:ByteArray = BackgroundFetch.AESEncryptWithKey(key, doubleData);
			var returnValue:ByteArray = new ByteArray();
			returnValue.writeBytes(aesBytes, 0, 8);
			return returnValue;
		}
		
		public static function cryptKey():ByteArray {
			var transmitterId:String = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TRANSMITTER_ID);
			var returnValue:ByteArray =  new ByteArray();
			returnValue.writeMultiByte("00" + transmitterId + "00" + transmitterId,"iso-8859-1");
			return returnValue;
		}
		
		private static function processBLUKONTransmitterData(buffer:ByteArray):void {
			myTrace("in processBLUKONTransmitterData with blukonCurrentcomand = " + blukonCurrentCommand);
			if (buffer == null) {
				myTrace("in processBLUKONTransmitterData, null buffer passed to decodeBlukonPacket");
				return;
			}
			buffer.position = 0;
			buffer.endian = Endian.LITTLE_ENDIAN;
			var strRecCmd:String = utils.UniqueId.bytesToHex(buffer).toLowerCase();
			buffer.position = 0;
			var blueToothServiceEvent:BlueToothServiceEvent  = null;
			var gotLowBat:Boolean = false;
			
			var cmdFound:int = 0;
			
			if (strRecCmd == "cb010000") {
				myTrace("in processBLUKONTransmitterData, Reset currentCommand");
				blukonCurrentCommand = "";
				cmdFound = 1;
			}
			
			// BlukonACKRespons will come in two different situations
			// 1) after we have sent an ackwakeup command
			// 2) after we have a sleep command
			if (strRecCmd.indexOf("8b0a00") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, Got ACK");
				
				if (blukonCurrentCommand.indexOf("810a00") == 0) {//ACK sent
					//ack received
					blukonCurrentCommand = "010d0b00";
					myTrace("in processBLUKONTransmitterData, getUnknownCmd1: " + blukonCurrentCommand);
					
				} else {
					myTrace("in processBLUKONTransmitterData, Got sleep ack, resetting initialstate!");
					blukonCurrentCommand = "";
				}
			}
			
			if (strRecCmd.indexOf("8b1a02") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, Got NACK on cmd=" + blukonCurrentCommand + " with error=" + strRecCmd.substring(6));
				
				if (strRecCmd.indexOf("8b1a020014") == 0) {
					myTrace("in processBLUKONTransmitterData, Timeout: please wait 5min or push button to restart!");
				}
				
				if (strRecCmd.indexOf("8b1a02000f") == 0) {
					myTrace("in processBLUKONTransmitterData, Libre sensor has been removed!");
				}
				
				if (strRecCmd.indexOf("8b1a020011") == 0) {
					myTrace("in processBLUKONTransmitterData, Patch read error.. please check the connectivity and re-initiate... or maybe battery is low?, dispatching GLUCOSE_PATCH_READ_ERROR event");
					CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "1");
					gotLowBat = true;
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.GLUCOSE_PATCH_READ_ERROR);
					_instance.dispatchEvent(blueToothServiceEvent);
				}

				m_getNowGlucoseDataCommand = false;
				m_getNowGlucoseDataIndexCommand = false;
				blukonCurrentCommand = "";
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_TIME_STAMP_LAST_SENSOR_AGE_CHECK_IN_MS, "0");// set to 0  to force timer to be set back
			}
			
			if (blukonCurrentCommand == "" && strRecCmd == "cb010000") {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, wakeup received");
				
				blukonCurrentCommand = "010d0900";
				myTrace("in processBLUKONTransmitterData, getPatchInfo");
				
			} else if (blukonCurrentCommand.indexOf("010d0900") == 0 /*getPatchInfo*/ && strRecCmd.indexOf("8bd9") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, Patch Info received");
				
				buffer.position = 17;
				if (isSensorReady(buffer.readByte())) {
					blukonCurrentCommand = "810a00";
					myTrace("in processBLUKONTransmitterData, Send ACK");
				} else {
					blukonCurrentCommand = "";
					myTrace("in processBLUKONTransmitterData, Sensor is not ready, stop!");
				}
			} else if (blukonCurrentCommand.indexOf("010d0b00") == 0 /*getUnknownCmd1*/ && strRecCmd.indexOf("8bdb") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, gotUnknownCmd1 (010d0b00): "+strRecCmd);
				
				if (!strRecCmd.indexOf("8bdb0101041711") == 0) {
					myTrace("in processBLUKONTransmitterData, gotUnknownCmd1 (010d0b00): "+strRecCmd);
				}
				
				blukonCurrentCommand = "010d0a00";
				myTrace("in processBLUKONTransmitterData, getUnknownCmd2 "+ blukonCurrentCommand);
				
			} else if (blukonCurrentCommand.indexOf("010d0a00") == 0 /*getUnknownCmd2*/ && strRecCmd.indexOf("8bda") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, gotUnknownCmd2 (010d0a00): "+strRecCmd);
				
				if (strRecCmd != "8bdaaa") {
					myTrace("in processBLUKONTransmitterData, gotUnknownCmd2 (010d0a00): "+strRecCmd);
				}
				if (strRecCmd == "8bda02") {
					myTrace("in processBLUKONTransmitterData, gotUnknownCmd2: is maybe battery low????");
					CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "5");
					gotLowBat = true;
				}
				
				if ((new Date()).valueOf() - new Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TIME_STAMP_LAST_SENSOR_AGE_CHECK_IN_MS)) > GET_SENSOR_AGE_DELAY_IN_SECONDS * 1000) {
					blukonCurrentCommand = "010d0e0127";
					myTrace("in processBLUKONTransmitterData, getSensorAge");
				} else {
					if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_EXTERNAL_ALGORITHM) == "true") {
						myTrace("in processBLUKONTransmitterData, getHistoricData (2)");
						blukonCurrentCommand = "010d0f02002b";
						m_blockNumber = 0;
					} else {
						blukonCurrentCommand = "010d0e0103";
						m_getNowGlucoseDataIndexCommand = true;//to avoid issue when gotNowDataIndex cmd could be same as getNowGlucoseData (case block=3)
						myTrace("in processBLUKONTransmitterData, getNowGlucoseDataIndexCommand");
					}
				}
			} else if (blukonCurrentCommand.indexOf("010d0e0127") == 0 /*getSensorAge*/ && strRecCmd.indexOf("8bde") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, SensorAge received");
				
				buffer.position = 0;
				FSLSensorAGe = sensorAge(buffer);
				
				if ((FSLSensorAGe > 0) && (FSLSensorAGe < 200000)) {
				} else {
					myTrace("in processBLUKONTransmitterData, setting sensor age to Number.NAN");
					FSLSensorAGe = Number.NaN;
				}
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_TIME_STAMP_LAST_SENSOR_AGE_CHECK_IN_MS, (new Date()).valueOf().toString());
				if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_EXTERNAL_ALGORITHM) == "true") {
					myTrace("in processBLUKONTransmitterData, getHistoricData (3)");
					blukonCurrentCommand = "010d0f02002b";
					m_blockNumber = 0;
				} else {
					blukonCurrentCommand = "010d0e0103";
					m_getNowGlucoseDataIndexCommand = true;//to avoid issue when gotNowDataIndex cmd could be same as getNowGlucoseData (case block=3)
					myTrace("in processBLUKONTransmitterData, getNowGlucoseDataIndexCommand");
				}
			} else if (blukonCurrentCommand.indexOf("010d0e0103") == 0 /*getNowDataIndex*/ && m_getNowGlucoseDataIndexCommand && strRecCmd.indexOf("8bde") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, gotNowDataIndex");
				
				var delayedTrendIndex:int;
				var i:int;
				var delayedBlockNumber:String;
				// calculate time delta to last valid BG reading
				var bgReadings:Array = BgReading.latest(1);
				if (bgReadings.length > 0) {
					var bgReading:BgReading = (BgReading.latest(1))[0]  as BgReading;
					m_persistentTimeLastBg = bgReading.timestamp;
				} else {
					m_persistentTimeLastBg = 0;
				}
				m_minutesDiffToLastReading = ((((new Date()).valueOf() - m_persistentTimeLastBg)/1000)+30)/60;
				myTrace("in processBLUKONTransmitterData, m_minutesDiffToLastReading=" + m_minutesDiffToLastReading + ", last reading: " + (new Date(m_persistentTimeLastBg)).toString());
				
				// check time range for valid backfilling
				if ( (m_minutesDiffToLastReading > 7) && (m_minutesDiffToLastReading < (8*60))  ) {
					myTrace("in processBLUKONTransmitterData, start backfilling");
					m_getOlderReading = true;
				} else {
					m_getOlderReading = false;
				}
				// get index to current BG reading
				m_currentBlockNumber = blockNumberForNowGlucoseData(buffer);
				m_currentOffset = nowGlucoseOffset;
				// time diff must be > 5,5 min and less than the complete trend buffer
				if ( !m_getOlderReading ) {
					blukonCurrentCommand = "010d0e010" + m_currentBlockNumber;//getNowGlucoseData
					nowGlucoseOffset = m_currentOffset;
					myTrace("in processBLUKONTransmitterData, getNowGlucoseData");
				}
				else {
					m_minutesBack = m_minutesDiffToLastReading;
					delayedTrendIndex = m_currentTrendIndex;
					// ensure to have min 3 mins distance to last reading to avoid doible draws (even if they are distict)
					if ( m_minutesBack > 17 ) {
						m_minutesBack = 15;
					} else if ( m_minutesBack > 12 ) {
						m_minutesBack = 10;
					} else if ( m_minutesBack > 7 ) {
						m_minutesBack = 5;
					}
					myTrace("in processBLUKONTransmitterData, read " + m_minutesBack + " mins old trend data");
					for ( i = 0 ; i < m_minutesBack ; i++ ) {
						if ( --delayedTrendIndex < 0)
							delayedTrendIndex = 15;
					}
					delayedBlockNumber = blockNumberForNowGlucoseDataDelayed(delayedTrendIndex);
					blukonCurrentCommand = "010d0e010" + delayedBlockNumber;//getNowGlucoseData
					myTrace("in processBLUKONTransmitterData, getNowGlucoseData backfilling");
				}
				m_getNowGlucoseDataIndexCommand = false;
				m_getNowGlucoseDataCommand = true;
			} else if (blukonCurrentCommand.indexOf("010d0e01") == 0 /*getNowGlucoseData*/ && m_getNowGlucoseDataCommand && strRecCmd.indexOf("8bde") == 0) {
				cmdFound = 1;
				var currentGlucose:Number = nowGetGlucoseValue(buffer);
				myTrace("in processBLUKONTransmitterData, *****************got getNowGlucoseData = " + currentGlucose);
				
				if (!m_getOlderReading) {
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
					blueToothServiceEvent.data = new TransmitterDataBluKonPacket(currentGlucose, 0, 0, FSLSensorAGe, (new Date()).valueOf());
					FSLSensorAGe = Number.NaN;
					
					blukonCurrentCommand = "010c0e00";
					myTrace("in processBLUKONTransmitterData, Send sleep cmd");
					m_getNowGlucoseDataCommand = false;
				} else {
					myTrace("in processBLUKONTransmitterData, bf: processNewTransmitterData with delayed timestamp of " + m_minutesBack + " min");
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
					blueToothServiceEvent.data = new TransmitterDataBluKonPacket(currentGlucose, 0, 0, 0 /*battery level force to 0 as unknown*/, (new Date()).valueOf() - (m_minutesBack*60*1000));
					m_minutesBack -= 5;
					if ( m_minutesBack < 5 ) {
						m_getOlderReading = false;
					}
					myTrace("in processBLUKONTransmitterData,bf: calculate next trend buffer with " + m_minutesBack + " min timestamp");
					delayedTrendIndex = m_currentTrendIndex;
					for ( i = 0 ; i < m_minutesBack ; i++ ) {
						if ( --delayedTrendIndex < 0)
							delayedTrendIndex = 15;
					}
					delayedBlockNumber = blockNumberForNowGlucoseDataDelayed(delayedTrendIndex);
					blukonCurrentCommand = "010d0e010" + delayedBlockNumber;//getNowGlucoseData
					myTrace("in processBLUKONTransmitterData, bf: read next block: " + blukonCurrentCommand);
				}
			} else if ((blukonCurrentCommand.indexOf("010d0f02002b") == 0 || (blukonCurrentCommand == "" && m_blockNumber > 0)) && strRecCmd.indexOf("8bdf") == 0) {
				cmdFound = 1;
				buffer.position = 0;
				handlegetHistoricDataResponse(buffer);
			} else if (strRecCmd.indexOf("cb020000") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, is bridge battery low????!");
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "3");
				gotLowBat = true;
			} else if (strRecCmd.indexOf("cbdb0000") == 0) {
				cmdFound = 1;
				myTrace("in processBLUKONTransmitterData, is bridge battery really low????!");
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "2");
				gotLowBat = true;
			} 
			
			if (!gotLowBat) {
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_BLUKON_BATTERY_LEVEL, "100");
			}	
			
			
			if (blukonCurrentCommand.length > 0 && cmdFound == 1) {
				myTrace("in processBLUKONTransmitterData, Sending reply: " + blukonCurrentCommand);
				sendCommand(blukonCurrentCommand);
			} else {
				if (cmdFound == 0) {
					myTrace("in processBLUKONTransmitterData, ************COMMAND NOT FOUND! -> " + strRecCmd + " on currentCmd=" + blukonCurrentCommand);
					blukonCurrentCommand = "";
				}
			}
			
			if (blueToothServiceEvent != null) {
				myTrace("in processBlukonTransmitterData, dispatching transmitter data");
				_instance.dispatchEvent(blueToothServiceEvent);
			}
		}
		
		private static function handlegetHistoricDataResponse(buffer:ByteArray):void {
			myTrace("in handlegetHistoricDataResponse, recieved historic data, m_block_number = " + m_blockNumber);
			// We are looking for 43 blocks of 8 bytes.
			// The bluekon will send them as 21 blocks of 16 bytes, and the last one of 8 bytes. 
			// The packet will look like "0x8b 0xdf 0xblocknumber 0x02 DATA" (so data starts at place 4)
			if(m_blockNumber > 42) {
				myTrace("in handlegetHistoricDataResponse, recieved historic data, but block number is too big " + m_blockNumber);
				return;
			}
			
			var len:int = buffer.length - 4;
			buffer.position = 2;
			var buffer_at_2:int = buffer.readByte();
			myTrace("in handlegetHistoricDataResponse, len = " + len +" " + len + " blocknum " + buffer_at_2);
			
			if(buffer_at_2 != m_blockNumber) {
				myTrace("in handlegetHistoricDataResponse, We have recieved a bad block number buffer[2] = " + buffer_at_2 + " m_blockNumber = " + m_blockNumber);
				return;
			}
			if(8 * m_blockNumber + len > m_full_data.length) {
				myTrace("in handlegetHistoricDataResponse, We have recieved too much data  m_blockNumber = " + m_blockNumber + " len = " + len + 
					" m_full_data.length = " + m_full_data.length);        	
				return;
			}
			
			buffer.position = 4;
			buffer.readBytes(m_full_data, 8 * m_blockNumber, len);
			m_blockNumber += len / 8;
			
			if(m_blockNumber >= 43) {
				blukonCurrentCommand = "010c0e00";
				myTrace("in handlegetHistoricDataResponse, Send sleep cmd");
				myTrace("in handlegetHistoricDataResponse, Full data that was recieved is " + utils.UniqueId.bytesToHex(m_full_data));
			} else {
				blukonCurrentCommand = "";
			}
		}
		
		private static function sensorAge(input:ByteArray):int {
			input.position = 3 + 4;
			var value3plus4:int = input.readByte();
			input.position = 3 + 5;
			var value3plus5:int = input.readByte();

			var returnValue:int = ((value3plus5 & 0xFF) << 8) | (value3plus4 & 0xFF);
			myTrace("in sensorAge, sensorAge = " + returnValue);
			
			return returnValue;
		}
		
		private static function blockNumberForNowGlucoseData(input:ByteArray):String {
			input.position = 5;
			var nowGlucoseIndex2:int = 0;
			var nowGlucoseIndex3:int = 0;
			
			nowGlucoseIndex2 = input.readByte();
			
			// caculate byte position in sensor body
			nowGlucoseIndex2 = (nowGlucoseIndex2 * 6) + 4;
			
			// decrement index to get the index where the last valid BG reading is stored
			nowGlucoseIndex2 -= 6;
			// adjust round robin
			if ( nowGlucoseIndex2 < 4 )
				nowGlucoseIndex2 = nowGlucoseIndex2 + 96;
			
			// calculate the absolute block number which correspond to trend index
			nowGlucoseIndex3 = 3 + (nowGlucoseIndex2/8);
			
			// calculate offset of the 2 bytes in the block
			nowGlucoseOffset = nowGlucoseIndex2 % 8;
			
			var nowGlucoseDataAsHexString:String = nowGlucoseIndex3.toString(16);
			return nowGlucoseDataAsHexString;
		}
		
		private static function blockNumberForNowGlucoseDataDelayed(delayedIndex:int):String
		{
			var i:int;
			var ngi2:int;
			var ngi3:int;
			
			// calculate byte offset in libre FRAM
			ngi2 = (delayedIndex * 6) + 4;
			
			ngi2 -= 6;
			if (ngi2 < 4)
				ngi2 = ngi2 + 96;
			
			// calculate the block number where to get the BG reading
			ngi3 = 3 + (ngi2/8);
			
			// calculate the offset in the block
			nowGlucoseOffset = ngi2 % 8;
			myTrace("in blockNumberForNowGlucoseDataDelayed, ++++++++backfillingTrendData: index " + delayedIndex + ", block " + ngi3.toString(16) + ", offset " + nowGlucoseOffset);
			
			return(ngi3.toString(16));
		}
		
		public static function nowGetGlucoseValue(input:ByteArray):Number {
			input.position = 3 + nowGlucoseOffset;
			var curGluc:Number;
			var rawGlucose:Number;
			
			// grep 2 bytes with BG data from input bytearray, mask out 12 LSB bits and rescale for xDrip+
			//rawGlucose = (input[3+m_nowGlucoseOffset+1]&0x0F)*16 + input[3+m_nowGlucoseOffset];
			var value1:int = input.readByte();
			var value2:int = input.readByte();
			rawGlucose = ((value2 & 0x0F)<<8) | (value1 & 0xFF);
			myTrace("in nowGetGlucoseValue rawGlucose=" + rawGlucose);
			
			// rescale
			curGluc = LibreAlarmReceiver.getGlucose(rawGlucose);
			
			return(curGluc);
		}
		
		/**
		 * sends the command to  WriteCharacteristic and also assigns blukonCurrentCommand to command
		 */
		private static function sendCommand(command:String):void {
			if (!activeBluetoothPeripheral.writeValueForCharacteristic(writeCharacteristic, utils.UniqueId.hexStringToByteArray(command))) {
				myTrace("send " + command + " failed");
			} else {
				myTrace("send " + command + " succesfull");
			}
		}
		
		public static function processTRANSMITER_PLTransmitterData(buffer:ByteArray):void {
			buffer.endian = Endian.LITTLE_ENDIAN;
			
			buffer.position = 0;
			var bufferAsString:String = buffer.readUTFBytes(buffer.length);
			myTrace("in processTRANSMITER_PLTransmitterData buffer as string =  " + bufferAsString);
			var bufferAsStringSplitted:Array = bufferAsString.split(/\s/);
			if (bufferAsStringSplitted.length > 1) {
				if (bufferAsStringSplitted[0] == "000999") {
					if (bufferAsStringSplitted[1] == "0001") {
						myTrace("in processTRANSMITER_PLTransmitterData, error code 0001, to low voltage for nfc reading");
						if (BackgroundFetch.appIsInForeground()) {
							AlertManager.showSimpleAlert
							(
								"Error",
								"Voltage is too low for NFC reading.",
								4 * 60 + 30
							);
						} 					
					} else if (bufferAsStringSplitted[1] == "0002") {
						myTrace("in processTRANSMITER_PLTransmitterData, error code 0002, please check position of device. Is it fixed on sensor ? ");
						if (BackgroundFetch.appIsInForeground()) {
							AlertManager.showSimpleAlert
								(
									"Error",
									"Please check your Transmiter PL. Is it correctly fixed to the sensor?",
									4 * 60 + 30
								);
						} 					
					} else {
						myTrace("in processTRANSMITER_PLTransmitterData, Error code = " + bufferAsStringSplitted[1] + ", call the service man");
						if (BackgroundFetch.appIsInForeground()) {
							AlertManager.showSimpleAlert
								(
									"Error",
									"Error code = " + bufferAsStringSplitted[1] + ". Contact manufacturer support.",
									4 * 60 + 30
								);
						} 					
					}
					return;
				}
			}
			if (bufferAsStringSplitted.length < 4) {
				myTrace("in processTRANSMITER_PLTransmitterData. Response has less than 4 elements, no further processing");
				return;
			}
			var raw_data:Number = new Number(bufferAsStringSplitted[0]);
			if (isNaN(raw_data)) {
				myTrace("in processTRANSMITER_PLTransmitterData, data doesn't start with an Integer, no further processing");
				return;
			}
			var bridge_battery_level:Number = new Number(bufferAsStringSplitted[2]);
			
			var sensorAge:Number = (new Number(bufferAsStringSplitted[3])) * 10;
			//see https://github.com/JohanDegraeve/iosxdripreader/issues/42
			if (previousSensorAgeValue_Transmiter_PL != 0) {
				if (previousSensorAgeValue_Transmiter_PL <= sensorAge) {
					myTrace("in processTRANSMITER_PLTransmitterData, previousSensorAgeValue_Transmiter_PL = " + previousSensorAgeValue_Transmiter_PL + ", sensorAge = " + sensorAge);
					if ((new Date()).valueOf() - timeStampSinceLastSensorAgeUpdate_Transmiter_PL > 10 * 60 * 1000) {
						myTrace("in processTRANSMITER_PLTransmitterData, timeStampSinceLastSensorAgeUpdate_Transmiter_PL = " + new Date(timeStampSinceLastSensorAgeUpdate_Transmiter_PL).toLocaleString());
						LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES, 
							(new Number(new Number(LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES))) + 1).toString());
						if (new Number(LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES)) >= 5) {
							myTrace("in processTRANSMITER_PLTransmitterData, LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES = " + LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES);
							if (BackgroundFetch.appIsInForeground()) 
							{
								AlertManager.showSimpleAlert
								(
									ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"),
									ModelLocator.resourceManagerInstance.getString("bluetoothservice","dead_or_expired_sensor")
								);
								BackgroundFetch.vibrate();
							} else {
								var notificationBuilder:NotificationBuilder = new NotificationBuilder()
										.setId(NotificationService.ID_FOR_DEAD_OR_EXPIRED_SENSOR_TRANSMITTER_PL)
										.setAlert(ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"))
										.setTitle(ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"))
										.setBody(ModelLocator.resourceManagerInstance.getString("bluetoothservice","dead_or_expired_sensor"))
										.enableVibration(true)
								Notifications.service.notify(notificationBuilder.build());
							}
						}
					}
				} else {
					timeStampSinceLastSensorAgeUpdate_Transmiter_PL = (new Date()).valueOf();
					LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_TRANSMITER_PL_AMOUNT_OF_INVALID_SENSOR_AGE_VALUES, "0");
				}
			}
			previousSensorAgeValue_Transmiter_PL = sensorAge;

			myTrace("in processTRANSMITER_PLTransmitterData, dispatching transmitter data");
			var blueToothServiceEvent:BlueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
			blueToothServiceEvent.data = new TransmitterDataTransmiter_PLPacket(raw_data, bridge_battery_level, sensorAge, (new Date()).valueOf());
			_instance.dispatchEvent(blueToothServiceEvent);
		}
		
		public static function processBlueReaderTransmitterData(buffer:ByteArray):void {
			buffer.position = 0;
			buffer.endian = Endian.LITTLE_ENDIAN;
			myTrace("in processBlueReaderTransmitterData data packet received from transmitter : " + utils.UniqueId.bytesToHex(buffer));

			buffer.position = 0;
			var bufferAsString:String = buffer.readUTFBytes(buffer.length);
			var blueToothServiceEvent:BlueToothServiceEvent;
			myTrace("in processBlueReaderTransmitterData buffer as string =  " + bufferAsString);
			if (buffer.length >= 7) {
				if (bufferAsString.toUpperCase().indexOf("BATTERY") > -1) {
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
					blueToothServiceEvent.data = new TransmitterDataBlueReaderBatteryPacket();
					_instance.dispatchEvent(blueToothServiceEvent);
					return;
				}
			}
			
			myTrace("in processBlueReaderTransmitterData, it's not a battery message, continue processing");
			var bufferAsStringSplitted:Array = bufferAsString.split(/\s/);
			var raw_data:Number = new Number(bufferAsStringSplitted[0]);

			if (isNaN(raw_data)) {
				myTrace("in processBlueReaderTransmitterData, data doesn't start with an Integer, no further processing");
				return;
			}
			myTrace("in processBlueReaderTransmitterData, raw_data = " + raw_data.toString())
			
			var blueReaderBatteryLevel:Number = Number.NaN; 
			var fslBatteryLevel:Number = Number.NaN;
			var sensorAge:Number = Number.NaN;
			if (bufferAsStringSplitted.length > 1) {
				blueReaderBatteryLevel = new Number(bufferAsStringSplitted[1]);
				myTrace("in processBlueReaderTransmitterData, blueReaderBatteryLevel = " + blueReaderBatteryLevel.toString());
				if (bufferAsStringSplitted.length > 2) {
					fslBatteryLevel = new Number(bufferAsStringSplitted[2]);
					myTrace("in processBlueReaderTransmitterData, fslBatteryLevel = " + fslBatteryLevel.toString());
					if (bufferAsStringSplitted.length > 3) {
						sensorAge = new Number(bufferAsStringSplitted[3]);
						myTrace("in processBlueReaderTransmitterData, sensorAge = " + sensorAge.toString());
					}
				}
			}
			myTrace("in processBlueReaderTransmitterData, dispatching transmitter data with blueReaderBatteryLevel = " + blueReaderBatteryLevel + ", fslBatteryLevel = " + fslBatteryLevel);
			blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
			blueToothServiceEvent.data = new TransmitterDataBlueReaderPacket(raw_data, blueReaderBatteryLevel, fslBatteryLevel, sensorAge, (new Date()).valueOf());
			_instance.dispatchEvent(blueToothServiceEvent);
		}
		
		private static function processG4TransmitterData(buffer:ByteArray):void {
			myTrace("in processG4TransmitterData");
			buffer.endian = Endian.LITTLE_ENDIAN;
			var packetLength:int = buffer.readUnsignedByte();
			var packetType:int = buffer.readUnsignedByte();//0 = data packet, 1 =  TXID packet, 0xF1 (241 if read as unsigned int) = Beacon packet
			var txID:Number;
			var xBridgeProtocolLevel:Number;
			var blueToothServiceEvent:BlueToothServiceEvent;
			var bridgeBatteryPercentage:Number;
			switch (packetType) {
				case 0:
					//data packet
					var rawData:Number = buffer.readInt();
					var filteredData:Number = buffer.readInt();
					var transmitterBatteryVoltage:Number = buffer.readUnsignedByte();
					
					if (packetLength == 21) {//xbridge with protocol that has also the timestamp, example xbridger
						//could also be for dexbridgewixel, however not yet tested for that
						bridgeBatteryPercentage = buffer.readUnsignedByte();
						txID = buffer.readInt();
						var timestamp:Number = ((new Date()).valueOf() - buffer.readInt());
						//xBridgeProtocolLevel = buffer.readUnsignedByte();
						myTrace("in processG4TransmitterData, with bridgeBatteryPercentage = " + bridgeBatteryPercentage + ", txID = " + decodeTxID(txID) + ", timestamp = " + utils.DateTimeUtilities.createNSFormattedDateAndTime(new Date(timestamp)));
						
						blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
						blueToothServiceEvent.data = new TransmitterDataXBridgeRDataPacket(rawData, filteredData, transmitterBatteryVoltage, bridgeBatteryPercentage, decodeTxID(txID), timestamp);
						_instance.dispatchEvent(blueToothServiceEvent);
					} else if (packetLength == 17) {//xbridge
						//following only if the name of the device contains "bridge", if it' doesnt contain bridge, then it's an xdrip (old) and doesn't have those bytes' +
						//or if packetlenth == 17, why ? because it could be a drip with xbridge software but still with a name xdrip, because it was originally an xdrip that was later on overwritten by the xbridge software, in that case the name will still by xdrip and not xbridge
						bridgeBatteryPercentage = buffer.readUnsignedByte();
						txID = buffer.readInt();
						xBridgeProtocolLevel = buffer.readUnsignedByte();
						
						blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
						blueToothServiceEvent.data = new TransmitterDataXBridgeDataPacket(rawData, filteredData, transmitterBatteryVoltage, bridgeBatteryPercentage, decodeTxID(txID));
						_instance.dispatchEvent(blueToothServiceEvent);
					} else {
						blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
						blueToothServiceEvent.data = new TransmitterDataXdripDataPacket(rawData, filteredData, transmitterBatteryVoltage);
						_instance.dispatchEvent(blueToothServiceEvent);
					}
					
					break;
				case 1://will actually never happen, this is a packet type for the other direction , ie from App to xbridge
					//TXID packet
					txID = buffer.readInt();
					break;
				case 241:
					//Beacon packet
					txID = buffer.readInt();
					
					blueToothServiceEvent = new BlueToothServiceEvent(BlueToothServiceEvent.TRANSMITTER_DATA);
					blueToothServiceEvent.data = new TransmitterDataXBridgeBeaconPacket(decodeTxID(txID));
					_instance.dispatchEvent(blueToothServiceEvent);
					
					xBridgeProtocolLevel = buffer.readUnsignedByte();//not needed for the moment
					break;
				default:
					myTrace("processG4TransmitterData unknown packetType received : " + packetType);
					warnUnknownG4PacketType(packetType);
			}
		}
		
		public static function warnUnknownG4PacketType(packetType:int):void {
			if (BackgroundFetch.appIsInBackground()) {
				return;
			}
			if ((new Date()).valueOf() - new Number(LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_TIMESTAMP_SINCE_LAST_INFO_UKNOWN_PACKET_TYPE)) < 30 * 60 * 1000)
				return;
			if (LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_DONTASKAGAIN_ABOUT_UNKNOWN_PACKET_TYPE) ==  "true") {
				return;
			}
			if (listOfSeenInvalidPacketTypes.indexOf(packetType) > -1) {
				unsupportedPacketType = packetType;
				
				var alert:Alert = AlertManager.showActionAlert
					(
						ModelLocator.resourceManagerInstance.getString('bluetoothservice', "xdrip_alert_title"),
						ModelLocator.resourceManagerInstance.getString('bluetoothservice', "unknownpackettypeinfo"),
						Number.NaN,
						[
							{ label: ModelLocator.resourceManagerInstance.getString("globaltranslations","cancel_button_label").toUpperCase() },
							{ label: ModelLocator.resourceManagerInstance.getString('bluetoothservice', "dontaskagain") },
							{ label: ModelLocator.resourceManagerInstance.getString('bluetoothservice', "notnow") },
							{ label: ModelLocator.resourceManagerInstance.getString('bluetoothservice', "sendemail") }
						]
					)
				alert.height = 320;
				alert.buttonGroupProperties.gap = -5;
				alert.width = 310;
				alert.addEventListener( starling.events.Event.CLOSE, sendemail );
			}
		}
		
		private static function sendemail(e:starling.events.Event, data:Object):void {
			if (data != null) {
				if (data.label == ModelLocator.resourceManagerInstance.getString("globaltranslations","cancel_button_label").toUpperCase()) {
					return;
				} else if (data.label == ModelLocator.resourceManagerInstance.getString('bluetoothservice', "notnow")) {
					LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_TIMESTAMP_SINCE_LAST_INFO_UKNOWN_PACKET_TYPE, (new Date()).valueOf().toString());
					return;
				} else if (data.label == ModelLocator.resourceManagerInstance.getString('bluetoothservice', "dontaskagain")) {
					LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_DONTASKAGAIN_ABOUT_UNKNOWN_PACKET_TYPE, "true");
					return;
				}
			}
			
			LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_TIMESTAMP_SINCE_LAST_INFO_UKNOWN_PACKET_TYPE, (new Date()).valueOf().toString());
			var body:String = "Hi,\n\nRequest for support wxl. Unsupported packetType =  " + unsupportedPacketType + ".\n\nregards.";
			G4WixelSender.displayWixelSender();
		}

		
		private static function myTrace(log:String):void {
			Trace.myTrace("BluetoothService.as", log);
		}
		
		/**
		 * returns true if activeBluetoothPeripheral != null
		 */
		public static function bluetoothPeripheralActive():Boolean {
			return activeBluetoothPeripheral != null;
		}
		
		public static function fullAuthenticateG5():void {
			myTrace("in fullAuthenticateG5");
			if (readCharacteristic != null) {
				sendAuthRequestTxMessage(readCharacteristic);
				awaitingAuthStatusRxMessage = true;
			} else {
				myTrace("fullAuthenticate: authCharacteristic is NULL!");
			}
		}
		
		private static function sendAuthRequestTxMessage(characteristic:Characteristic):void {
			authRequest = new AuthRequestTxMessage(getTokenSize());
			
			if (!activeBluetoothPeripheral.writeValueForCharacteristic(characteristic, authRequest.byteSequence)) {
				myTrace("sendAuthRequestTxMessage writeValueForCharacteristic failed");
			}
		}
		
		private static function getTokenSize():Number {
			return 8;
		}
		
		public static function getSensorData():void {
			myTrace("getSensorData");
			var sensorTx:SensorTxMessage = new SensorTxMessage();
			if (!activeBluetoothPeripheral.writeValueForCharacteristic(writeCharacteristic, sensorTx.byteSequence)) {
				myTrace("getSensorData writeValueForCharacteristic G5CommunicationCharacteristic failed");
			}
		}
		
		public static function startRescan(event:flash.events.Event):void {
			if (!(BluetoothLE.service.centralManager.state == BluetoothLEState.STATE_ON)) {
				myTrace("In startRescan but bluetooth is not on");
				return;
			}
			
			if (peripheralConnected) {
				myTrace("In startRescan but connected so returning");
				return;
			}
			
			if (!BluetoothLE.service.centralManager.isScanning) {
				myTrace("in startRescan calling bluetoothStatusIsOn");
				bluetoothStatusIsOn();
			} else {
				myTrace("in startRescan but already scanning, so returning");
				return;
			}
		}
		
		public static function getCharacteristicName(uuid:String):String {
			if (uuid.toUpperCase() == G5_Authentication_Characteristic_UUID.toUpperCase()) {
				return "G5_Authentication_Characteristic_UUID";
			} else if (uuid.toUpperCase() == G5_Control_Characteristic_UUID.toUpperCase()) {
				return "G5_Control_Characteristic_UUID";
			} else if (uuid.toUpperCase() == Blucon_TX_Characteristic_UUID.toUpperCase()) {
				return "Blucon_TX_Characteristic_UUID";
			} else if (uuid.toUpperCase() == Blucon_RX_Characteristic_UUID.toUpperCase()) {
				return "Blucon_RX_Characteristic_UUID";
			} else if (uuid.toUpperCase() == Transmiter_PL_RX_Characteristic_UUID.toUpperCase()) {
				return "Transmiter_PL_RX_Characteristics_UUID";
			} else if (uuid.toUpperCase() == Transmiter_PL_TX_Characteristic_UUID.toUpperCase()) {
				return "Transmiter_PL_TX_Characteristics_UUID";
			} else if (G4_RX_Characteristic_UUID.toUpperCase().indexOf(uuid.toUpperCase()) > -1) {
				return "G4_RX_Characteristic_UUID";
			} else if (uuid.toUpperCase() == BlueReader_RX_Characteristic_UUID.toUpperCase()) {
				return "BlueReader_RX_Characteristic_UUID";
			} else if (uuid.toUpperCase() == BlueReader_TX_Characteristic_UUID.toUpperCase()) {
				return "BlueReader_TX_Characteristic_UUID";
			} 
			return uuid + ", unknown characteristic uuid";
		}
		
		private static function isSensorReady(sensorStatusByte:int):Boolean {
			if (!ModelLocator.TEST_FLIGHT_MODE)
				return true;
			
			var sensorStatusString:String = "";
			var ret:Boolean = false;
			
			switch (sensorStatusByte) {
				case 1:
					sensorStatusString = "not yet started";
					break;
				case 2:
					sensorStatusString = "starting";
					ret = true;
					break;
				case 3:       // status for 14 days and 12 h of normal operation, abbott reader quits after 14 days
					sensorStatusString = "ready";
					ret = true;
					break;
				case 4:       // status of the following 12 h, sensor delivers last BG reading constantly
					sensorStatusString = "expired";
					//ret = true;
					break;
				case 5:		  // sensor stops operation after 15d after start
					sensorStatusString = "shutdown";
					//to use dead sensors for test
					//ret = true
					break;
				case 6:
					sensorStatusString = "in failure";
					break;
				default:
					sensorStatusString = "in an unknown state";
					break;
			}
			
			myTrace("in isSensorReady, sensor status is: " + sensorStatusString);
			
			if (!ret) {
				AlertManager.showSimpleAlert
					(
						ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"),
						ModelLocator.resourceManagerInstance.getString("bluetoothservice","cantusesensor") + " " + sensorStatusString,
						60
					);
			}
			return ret;
		}
		
		//not sure if this is needed
		//while trying to find a stable solution for blukon, this is being added. It's supposed to increase the iOS scanning frequency
		private static function startMonitoringAndRangingBeaconsInRegion(uuid:String):void {
			if (!startedMonitoringAndRangingBeaconsInRegion) {
				BackgroundFetch.startMonitoringAndRangingBeaconsInRegion(uuid);
				startedMonitoringAndRangingBeaconsInRegion = true;
			}
		}
		
		private static function stopMonitoringAndRangingBeaconsInRegion(uuid:String):void {
			if (startedMonitoringAndRangingBeaconsInRegion) {
				BackgroundFetch.stopMonitoringAndRangingBeaconsInRegion(uuid);
				startedMonitoringAndRangingBeaconsInRegion = false;
			}
		}
		
		private static function addBluetoothLEEventListeners():void {
			BluetoothLE.service.centralManager.addEventListener(PeripheralEvent.DISCOVERED, central_peripheralDiscoveredHandler);
			BluetoothLE.service.centralManager.addEventListener(PeripheralEvent.CONNECT, central_peripheralConnectHandler );
			BluetoothLE.service.centralManager.addEventListener(PeripheralEvent.CONNECT_FAIL, central_peripheralDisconnectHandler );
			BluetoothLE.service.centralManager.addEventListener(PeripheralEvent.DISCONNECT, central_peripheralDisconnectHandler );
			BluetoothLE.service.addEventListener(BluetoothLEEvent.STATE_CHANGED, bluetoothStateChangedHandler);
		}
		
		private static function removeBluetoothLEEventListeners():void {
			BluetoothLE.service.centralManager.removeEventListener(PeripheralEvent.DISCOVERED, central_peripheralDiscoveredHandler);
			BluetoothLE.service.centralManager.removeEventListener(PeripheralEvent.CONNECT, central_peripheralConnectHandler );
			BluetoothLE.service.centralManager.removeEventListener(PeripheralEvent.CONNECT_FAIL, central_peripheralDisconnectHandler );
			BluetoothLE.service.centralManager.removeEventListener(PeripheralEvent.DISCONNECT, central_peripheralDisconnectHandler );
			BluetoothLE.service.addEventListener(BluetoothLEEvent.STATE_CHANGED, bluetoothStateChangedHandler);
		}
		
		private static function addMiaoMiaoEventListeners():void {
			BackgroundFetch.instance.addEventListener(BackgroundFetchEvent.MIAO_MIAO_NEW_MAC, receivedMiaoMiaoDeviceAddress);
			BackgroundFetch.instance.addEventListener(BackgroundFetchEvent.MIAO_MIAO_DATA_PACKET_RECEIVED, receivedMiaoMiaoDataPacket);
			BackgroundFetch.instance.addEventListener(BackgroundFetchEvent.SENSOR_NOT_DETECTED_MESSAGE_RECEIVED_FROM_MIAOMIAO, receivedSensorNotDetectedFromMiaoMiao);
			BackgroundFetch.instance.addEventListener(BackgroundFetchEvent.SENSOR_CHANGED_MESSAGE_RECEIVED_FROM_MIAOMIAO, receivedSensorChangedFromMiaoMiao);
		}
		
		private static function receivedSensorChangedFromMiaoMiao(event:flash.events.Event):void {
			myTrace("in receivedSensorChangedFromMiaoMiao");
			Tomato.receivedSensorChangedFromMiaoMiao();
		}
		
		private static function receivedSensorNotDetectedFromMiaoMiao(event:flash.events.Event):void {
			myTrace("in receivedSensorNotDetectedFromMiaoMiao received sensor not detected");
			var notificationBuilder:NotificationBuilder = new NotificationBuilder()
				.setId(NotificationService.ID_FOR_SENSOR_NOT_DETECTED_MIAOMIAO)
				.setAlert(ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"))
				.setTitle(ModelLocator.resourceManagerInstance.getString("globaltranslations","warning_alert_title"))
				.setBody(ModelLocator.resourceManagerInstance.getString("bluetoothservice","sensor_not_detected_miaomiao"))
				.enableVibration(false)
				.setSound("");
			Notifications.service.notify(notificationBuilder.build());
			_amountOfConsecutiveSensorNotDetectedForMiaoMiao++;
		}
		
		private static function removeMiaoMiaoEventListeners():void {
			BackgroundFetch.instance.removeEventListener(BackgroundFetchEvent.MIAO_MIAO_NEW_MAC, receivedMiaoMiaoDeviceAddress);
			BackgroundFetch.instance.removeEventListener(BackgroundFetchEvent.MIAO_MIAO_DATA_PACKET_RECEIVED, receivedMiaoMiaoDataPacket);
			BackgroundFetch.instance.removeEventListener(BackgroundFetchEvent.SENSOR_NOT_DETECTED_MESSAGE_RECEIVED_FROM_MIAOMIAO, receivedSensorNotDetectedFromMiaoMiao);
		}
		
		private static function receivedMiaoMiaoDeviceAddress(event:BackgroundFetchEvent):void {
			if (!BlueToothDevice.isMiaoMiao()) {
				myTrace("in receivedMiaoMiaoDeviceAddress but not miaomiao device, not processing");
			} else {
				BlueToothDevice.address = event.data.MAC;
				BlueToothDevice.name = "MIAOMIAO";
			}
		}
		
		private static function receivedMiaoMiaoDataPacket(event:BackgroundFetchEvent):void {
			Notifications.service.cancel(NotificationService.ID_FOR_SENSOR_NOT_DETECTED_MIAOMIAO);
			_amountOfConsecutiveSensorNotDetectedForMiaoMiao = 0;
			if (!BlueToothDevice.isMiaoMiao()) {
				myTrace("in receivedMiaoMiaoDataPacket but not miaomiao device, not processing");
			} else {
				Tomato.decodeTomatoPacket(utils.UniqueId.hexStringToByteArray(event.data.packet as String));
			}
		}
		
		private static function setPeripheralUUIDs():void {
			if (BlueToothDevice.isDexcomG4()) {
				service_UUID = G4_Service_UUID;
				advertisement_UUID_Vector = new <String>[G4_Advertisement_UUID];
				characteristics_UUID_Vector = G4_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = G4_RX_Characteristic_UUID;
				TX_Characteristic_UUID = G4_TX_Characteristic_UUID;
			} else if (BlueToothDevice.isDexcomG5()) {
				service_UUID = G5_Service_UUID;
				advertisement_UUID_Vector = new <String>[G5_Advertisement_UUID];
				characteristics_UUID_Vector = G5_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = G5_Authentication_Characteristic_UUID;
				TX_Characteristic_UUID = G5_Control_Characteristic_UUID;
			} else if (BlueToothDevice.isBlueReader()) {
				service_UUID = BlueReader_Service_UUID;
				advertisement_UUID_Vector = new <String>[BlueReader_Advertisement_UUID];
				characteristics_UUID_Vector = BlueReader_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = BlueReader_RX_Characteristic_UUID;
				TX_Characteristic_UUID = BlueReader_TX_Characteristic_UUID;
			} else if (BlueToothDevice.isBluKon()) {
				service_UUID = Blucon_Service_UUID;
				advertisement_UUID_Vector = new <String>[Blucon_Advertisement_UUID];
				characteristics_UUID_Vector = Blucon_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = Blucon_RX_Characteristic_UUID;
				TX_Characteristic_UUID = Blucon_TX_Characteristic_UUID;
			} else if (BlueToothDevice.isTransmiter_PL()) {
				service_UUID = Transmiter_PL_Service_UUID;
				advertisement_UUID_Vector = new <String>[Transmiter_PL_Advertisement_UUID];
				characteristics_UUID_Vector = Transmiter_PL_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = Transmiter_PL_RX_Characteristic_UUID;
				TX_Characteristic_UUID = Transmiter_PL_TX_Characteristic_UUID;
			} else if (BlueToothDevice.isxBridgeR()) {
				service_UUID = xBridgeR_Service_UUID;
				advertisement_UUID_Vector = new <String>[xBridgeR_Advertisement_UUID];
				characteristics_UUID_Vector = xBridgeR_Characteristics_UUID_Vector;
				RX_Characteristic_UUID = xBridgeR_RX_Characteristic_UUID;
				TX_Characteristic_UUID = xBridgeR_TX_Characteristic_UUID;
			} 
		}
	}
}