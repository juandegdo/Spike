package services
{
	import com.freshplanet.ane.AirBackgroundFetch.BackgroundFetch;
	
	import flash.events.Event;
	import flash.utils.Dictionary;
	import flash.utils.setInterval;
	
	import database.BgReading;
	import database.BlueToothDevice;
	import database.Calibration;
	import database.CommonSettings;
	
	import events.CalibrationServiceEvent;
	import events.FollowerEvent;
	import events.SettingsServiceEvent;
	import events.TransmitterServiceEvent;
	import events.TreatmentsEvent;
	
	import model.ModelLocator;
	
	import starling.core.Starling;
	
	import treatments.TreatmentsManager;
	
	import ui.chart.GlucoseFactory;
	
	import utils.BgGraphBuilder;
	import utils.GlucoseHelper;
	import utils.MathHelper;
	import utils.SpikeJSON;
	import utils.TimeSpan;
	import utils.Trace;

	[ResourceBundle("generalsettingsscreen")]
	[ResourceBundle("widgetservice")]
	
	public class WidgetService
	{
		/* Constants */
		private static const TIME_1_HOUR:int = 60 * 60 * 1000;
		private static const TIME_2_HOURS:int = 2 * 60 * 60 * 1000;
		private static const TIME_1_MINUTE:int = 60 * 1000;
		
		/* Internal Variables */
		private static var displayTrendEnabled:Boolean = true;
		private static var displayDeltaEnabled:Boolean = true;
		private static var displayUnitsEnabled:Boolean = true;
		private static var initialGraphDataSet:Boolean = false;
		private static var dateFormat:String;
		private static var historyTimespan:int;
		private static var widgetHistory:int;
		private static var glucoseUnit:String;
		
		/* Objects */
		private static var months:Array;
		private static var startupGlucoseReadingsList:Array;
		private static var activeGlucoseReadingsList:Array = [];
		
		public function WidgetService()
		{
			throw new Error("WidgetService is not meant to be instantiated!");
		}
		
		public static function init():void
		{
			Trace.myTrace("WidgetService.as", "Service started!");
			
			BackgroundFetch.initUserDefaults();
			
			months = ModelLocator.resourceManagerInstance.getString('widgetservice','months').split(",");
			
			if (!BlueToothDevice.isFollower())
				Starling.juggler.delayCall(setInitialGraphData, 3);
			
			CommonSettings.instance.addEventListener(SettingsServiceEvent.SETTING_CHANGED, onSettingsChanged);
			TransmitterService.instance.addEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBloodGlucoseReceived);
			NightscoutService.instance.addEventListener(FollowerEvent.BG_READING_RECEIVED, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.NEW_CALIBRATION_EVENT, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, setInitialGraphData);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_ADDED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_DELETED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_UPDATED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.IOB_COB_UPDATED, onTreatmentRefresh);
			
			setInterval(updateTreatments, TIME_1_MINUTE);
		}
		
		private static function onSettingsChanged(e:SettingsServiceEvent):void
		{
			if (e.data == CommonSettings.COMMON_SETTING_DO_MGDL ||
				e.data == CommonSettings.COMMON_SETTING_URGENT_LOW_MARK ||
				e.data == CommonSettings.COMMON_SETTING_LOW_MARK ||
				e.data == CommonSettings.COMMON_SETTING_HIGH_MARK ||
				e.data == CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK ||
				e.data == CommonSettings.COMMON_SETTING_CHART_DATE_FORMAT || 
				e.data == CommonSettings.COMMON_SETTING_WIDGET_HISTORY_TIMESPAN
			)
			{
				setInitialGraphData();
			}
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE)
				BackgroundFetch.setUserDefaultsData("smoothLine", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS)
				BackgroundFetch.setUserDefaultsData("showMarkers", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL)
				BackgroundFetch.setUserDefaultsData("showMarkerLabel", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES)
				BackgroundFetch.setUserDefaultsData("showGridLines", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS)
				BackgroundFetch.setUserDefaultsData("lineThickness", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS)
				BackgroundFetch.setUserDefaultsData("markerRadius", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)
				BackgroundFetch.setUserDefaultsData("urgentHighColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)
				BackgroundFetch.setUserDefaultsData("highColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)
				BackgroundFetch.setUserDefaultsData("inRangeColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)
				BackgroundFetch.setUserDefaultsData("lowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)
				BackgroundFetch.setUserDefaultsData("urgenLowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)
				BackgroundFetch.setUserDefaultsData("markerColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)
				BackgroundFetch.setUserDefaultsData("axisColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)
				BackgroundFetch.setUserDefaultsData("axisFontColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)
				BackgroundFetch.setUserDefaultsData("backgroundColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)
				BackgroundFetch.setUserDefaultsData("backgroundOpacity", String(Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)) / 100));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)
				BackgroundFetch.setUserDefaultsData("gridLinesColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)
				BackgroundFetch.setUserDefaultsData("displayLabelsColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)
				BackgroundFetch.setUserDefaultsData("oldDataColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)).toString(16).toUpperCase());
		}
		
		private static function setInitialGraphData(e:Event = null):void
		{
			Trace.myTrace("WidgetService.as", "Setting initial widget data!");
			
			dateFormat = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_DATE_FORMAT);
			historyTimespan = int(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HISTORY_TIMESPAN));
			widgetHistory = historyTimespan * TIME_1_HOUR;
			activeGlucoseReadingsList = [];
			
			startupGlucoseReadingsList = ModelLocator.bgReadings.concat();
			var now:Number = new Date().valueOf();
			var latestGlucoseReading:BgReading = startupGlucoseReadingsList[startupGlucoseReadingsList.length - 1];
			
			for(var i:int = startupGlucoseReadingsList.length - 1 ; i >= 0; i--)
			{
				var timestamp:Number = (startupGlucoseReadingsList[i] as BgReading).timestamp;
				
				if (now - timestamp <= widgetHistory)
				{
					var currentReading:BgReading = startupGlucoseReadingsList[i] as BgReading;
					if (currentReading == null || currentReading.calculatedValue == 0 || currentReading.calibration == null)
						continue;
					
					var glucoseValue:Number = Number(BgGraphBuilder.unitizedString((startupGlucoseReadingsList[i] as BgReading).calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true"));
					if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
					{
						if (isNaN(glucoseValue) || glucoseValue < 40)
							glucoseValue = 38;
					}
					else
					{
						if (isNaN(glucoseValue) || glucoseValue < 2.2)
						glucoseValue = 2.2;
					}
					
					activeGlucoseReadingsList.push( { value: glucoseValue, time: getGlucoseTimeFormatted(timestamp, true), timestamp: timestamp } );
				}
				else
					break;
			}
			
			activeGlucoseReadingsList.reverse();
			
			//Graph Data
			//BackgroundFetch.setUserDefaultsData("chartData", JSON.stringify(activeGlucoseReadingsList));
			BackgroundFetch.setUserDefaultsData("chartData", SpikeJSON.stringify(activeGlucoseReadingsList));
			
			//Settings
			BackgroundFetch.setUserDefaultsData("smoothLine", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE));
			BackgroundFetch.setUserDefaultsData("showMarkers", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS));
			BackgroundFetch.setUserDefaultsData("showMarkerLabel", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL));
			BackgroundFetch.setUserDefaultsData("showGridLines", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES));
			BackgroundFetch.setUserDefaultsData("lineThickness", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS));
			BackgroundFetch.setUserDefaultsData("markerRadius", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS));
			
			//Display Labels Data
			if (latestGlucoseReading != null)
			{
				var timeFormatted:String = getGlucoseTimeFormatted(latestGlucoseReading.timestamp, false);
				var lastUpdate:String = getLastUpdate(latestGlucoseReading.timestamp) + ", " + timeFormatted;
				BackgroundFetch.setUserDefaultsData("latestWidgetUpdate", ModelLocator.resourceManagerInstance.getString('widgetservice','last_update_label') + " " + lastUpdate);
				BackgroundFetch.setUserDefaultsData("latestGlucoseTime", String(latestGlucoseReading.timestamp));
				BackgroundFetch.setUserDefaultsData("latestGlucoseValue", BgGraphBuilder.unitizedString(latestGlucoseReading.calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true"));
				BackgroundFetch.setUserDefaultsData("latestGlucoseSlopeArrow", latestGlucoseReading.slopeArrow());
				BackgroundFetch.setUserDefaultsData("latestGlucoseDelta", MathHelper.formatNumberToStringWithPrefix(Number(BgGraphBuilder.unitizedDeltaString(false, true))));
			}
			
			//Threshold Values
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
			{
				BackgroundFetch.setUserDefaultsData("urgenLowThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_LOW_MARK));
				BackgroundFetch.setUserDefaultsData("lowThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_LOW_MARK));
				BackgroundFetch.setUserDefaultsData("highThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_HIGH_MARK));
				BackgroundFetch.setUserDefaultsData("urgentHighThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK));
			}
			else
			{
				BackgroundFetch.setUserDefaultsData("urgenLowThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_LOW_MARK))))) * 10)) / 10));
				BackgroundFetch.setUserDefaultsData("lowThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_LOW_MARK))))) * 10)) / 10));
				BackgroundFetch.setUserDefaultsData("highThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_HIGH_MARK))))) * 10)) / 10));
				BackgroundFetch.setUserDefaultsData("urgentHighThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK))))) * 10)) / 10));
			}
				
			//Colors
			BackgroundFetch.setUserDefaultsData("urgenLowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("lowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("inRangeColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("highColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("urgentHighColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("oldDataColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("displayLabelsColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("markerColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("axisColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("axisFontColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("gridLinesColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("mainLineColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MAIN_LINE_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("backgroundColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)).toString(16).toUpperCase());
			BackgroundFetch.setUserDefaultsData("backgroundOpacity", String(Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)) / 100));
			
			//Glucose Unit
			BackgroundFetch.setUserDefaultsData("glucoseUnit", GlucoseHelper.getGlucoseUnit());
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
				BackgroundFetch.setUserDefaultsData("glucoseUnitInternal", "mgdl");
			else
				BackgroundFetch.setUserDefaultsData("glucoseUnitInternal", "mmol");
			
			//IOB & COB
			BackgroundFetch.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			BackgroundFetch.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
			
			//Translations
			BackgroundFetch.setUserDefaultsData("minAgo", ModelLocator.resourceManagerInstance.getString('widgetservice','minute_ago'));
			BackgroundFetch.setUserDefaultsData("hourAgo", ModelLocator.resourceManagerInstance.getString('widgetservice','hour_ago'));
			BackgroundFetch.setUserDefaultsData("ago", ModelLocator.resourceManagerInstance.getString('widgetservice','ago'));
			BackgroundFetch.setUserDefaultsData("now", ModelLocator.resourceManagerInstance.getString('widgetservice','now'));
			BackgroundFetch.setUserDefaultsData("openSpike", ModelLocator.resourceManagerInstance.getString('widgetservice','open_spike'));
			
			initialGraphDataSet = true;
		}
		
		private static function processChartGlucoseValues():void
		{
			//if (BlueToothDevice.isFollower())
			//{
				activeGlucoseReadingsList = removeDuplicates(activeGlucoseReadingsList);
				activeGlucoseReadingsList.sortOn(["timestamp"], Array.NUMERIC);
			//}
			
			var currentTimestamp:Number
			if (BlueToothDevice.isFollower())
				currentTimestamp = (activeGlucoseReadingsList[0] as Object).timestamp;
			else
				currentTimestamp = activeGlucoseReadingsList[0].timestamp;
			var now:Number = new Date().valueOf();
			
			while (now - currentTimestamp > widgetHistory) 
			{
				activeGlucoseReadingsList.shift();
				if (activeGlucoseReadingsList.length > 0)
					currentTimestamp = activeGlucoseReadingsList[0].timestamp;
				else
					break;
			}
		}
		
		private static function removeDuplicates(array:Array):Array
		{
			var dict:Dictionary = new Dictionary();
			
			for (var i:int = array.length-1; i>=0; --i)
			{
				var timestamp:String = String((array[i] as Object).timestamp);
				if (!dict[timestamp])
					dict[timestamp] = true;
				else
					array.splice(i,1);
			}
			
			dict = null;
			
			return array;
		}
		
		private static function updateTreatments():void
		{
			Trace.myTrace("WidgetService.as", "Sending updated IOB and COB values to widget!");
			
			var now:Number = new Date().valueOf();
			
			BackgroundFetch.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			BackgroundFetch.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
		}
		
		private static function onTreatmentRefresh(e:Event):void
		{
			updateTreatments();
		}
		
		private static function onBloodGlucoseReceived(e:Event):void
		{
			if (!initialGraphDataSet) //Compatibility with follower mode because we get a new glucose event before Spike sends the initial chart data.
				setInitialGraphData();
			
			Trace.myTrace("WidgetService.as", "Sending new glucose reading to widget!");
			
			var currentReading:BgReading;
			if (!BlueToothDevice.isFollower())
				currentReading = BgReading.lastNoSensor();
			else
				currentReading = BgReading.lastWithCalculatedValue();
			
			if ((Calibration.allForSensor().length < 2 && !BlueToothDevice.isFollower()) || currentReading == null || currentReading.calculatedValue == 0 || currentReading.calibration == null)
				return;
			
			var latestGlucoseValue:Number = Number(BgGraphBuilder.unitizedString(currentReading.calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true"));
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
			{
				if (isNaN(latestGlucoseValue) || latestGlucoseValue < 40)
					latestGlucoseValue = 38;
			}
			else
			{
				if (isNaN(latestGlucoseValue) || latestGlucoseValue < 2.2)
					latestGlucoseValue = 2.2;
			}
			
			activeGlucoseReadingsList.push( { value: latestGlucoseValue, time: getGlucoseTimeFormatted(currentReading.timestamp, true), timestamp: currentReading.timestamp } ); 
			processChartGlucoseValues();
			
			var now:Number = new Date().valueOf();
			
			//Save data to User Defaults
			BackgroundFetch.setUserDefaultsData("latestWidgetUpdate", ModelLocator.resourceManagerInstance.getString('widgetservice','last_update_label') + " " + getLastUpdate(currentReading.timestamp) + ", " + getGlucoseTimeFormatted(currentReading.timestamp, false));
			BackgroundFetch.setUserDefaultsData("latestGlucoseValue", BgGraphBuilder.unitizedString(currentReading.calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true"));
			BackgroundFetch.setUserDefaultsData("latestGlucoseSlopeArrow", currentReading.slopeArrow());
			BackgroundFetch.setUserDefaultsData("latestGlucoseDelta", MathHelper.formatNumberToStringWithPrefix(Number(BgGraphBuilder.unitizedDeltaString(false, true))));
			BackgroundFetch.setUserDefaultsData("latestGlucoseTime", String(currentReading.timestamp));
			//BackgroundFetch.setUserDefaultsData("chartData", JSON.stringify(activeGlucoseReadingsList));
			BackgroundFetch.setUserDefaultsData("chartData", SpikeJSON.stringify(activeGlucoseReadingsList));
			BackgroundFetch.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			BackgroundFetch.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
			BackgroundFetch.setUserDefaultsData("chartData", SpikeJSON.stringify(activeGlucoseReadingsList));
		}
		
		/**
		 * Utility
		 */
		private static function getLastUpdate(timestamp:Number):String
		{
			var glucoseDate:Date = new Date(timestamp);
			
			return months[glucoseDate.month] + " " + glucoseDate.date;
		}
		
		private static function getGlucoseTimeFormatted(timestamp:Number, formatForChartLabel:Boolean):String
		{
			var glucoseDate:Date = new Date(timestamp);
			var timeFormatted:String;
			
			if (dateFormat == null || dateFormat.slice(0,2) == "24")
			{
				if (formatForChartLabel)
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_24H, widgetHistory == TIME_2_HOURS);
				else
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_24H);
			}
			else
			{
				if (formatForChartLabel)
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_12H, widgetHistory == TIME_2_HOURS, widgetHistory == TIME_1_HOUR);
				else
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_12H);
			}
			
			return timeFormatted;
		}
	}
}