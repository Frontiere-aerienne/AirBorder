// Source-backed facility datasets, separate from airport-independent API logic.
// New airports are added here as data; do not infer airside access or opening hours.
export const FACILITY_CATALOG_VERSION = "2026-11-17.1";

export const FACILITY_CATALOG = Object.freeze({
  HND: Object.freeze({
    version: "2026-07-14.1",
    provider: "Haneda Airport and facility operator records",
    facilities: Object.freeze([
      {
        id: "hnd-work-boxes",
        airportCode: "HND",
        terminal: null,
        name: "Work booths / work boxes",
        category: "workPod",
        accessZone: "airportLandside",
        openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], start: "07:00", end: "21:30", timeZone: "Asia/Tokyo" }],
        hoursStatus: "officialRecordVerifyFreshness",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/work_box.html"
      },
      {
        id: "hnd-terminal-hotels",
        airportCode: "HND",
        terminal: null,
        name: "The Royal Park Hotel Tokyo Haneda (Transit)",
        category: "transitHotel",
        accessZone: "airside",
        openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], allDay: true, timeZone: "Asia/Tokyo" }],
        hoursStatus: "officialRecordVerifyAvailability",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/hotel.html"
      },
      {
        id: "hnd-shower-rooms",
        airportCode: "HND",
        terminal: null,
        name: "Haneda Airport shower rooms",
        category: "shower",
        accessZone: "airportLandside",
        openingWindows: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], allDay: true, timeZone: "Asia/Tokyo" }],
        hoursStatus: "officialRecordNoReservations",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/shower_room.html"
      },
      {
        id: "hnd-lounges",
        airportCode: "HND",
        terminal: null,
        name: "Haneda Airport lounges",
        category: "lounge",
        accessZone: "mixed",
        openingWindows: [],
        hoursStatus: "verifyOfficialSource",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/lounge.html"
      },
      {
        id: "hnd-observation-decks",
        airportCode: "HND",
        terminal: null,
        name: "Haneda observation decks",
        category: "attraction",
        accessZone: "airportLandside",
        openingWindows: [],
        hoursStatus: "verifyOfficialSource",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/service/facilities/observation_deck.html"
      },
      {
        id: "hnd-edo-koji",
        airportCode: "HND",
        terminal: "3",
        name: "Edo Koji",
        category: "foodAndAttraction",
        accessZone: "airportLandside",
        openingWindows: [],
        hoursStatus: "verifyOfficialSource",
        dayRoomVerified: false,
        officialRecordURL: "https://tokyo-haneda.com/en/shop_and_dine/search_r.html"
      },
      {
        id: "hnd-airport-garden",
        airportCode: "HND",
        terminal: "3",
        name: "Haneda Airport Garden",
        category: "foodHotelAndAttraction",
        accessZone: "nearbyLandside",
        openingWindows: [],
        hoursStatus: "verifyOperatorSource",
        dayRoomVerified: false,
        officialRecordURL: "https://www.shopping-sumitomo-rd.com/haneda/english/"
      }
    ])
  })
});
