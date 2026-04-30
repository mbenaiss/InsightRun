//
//  RouteMapView.swift
//  InsightRun
//
//  MapKit view for displaying workout route
//

import SwiftUI
import MapKit

struct RouteMapView: View {
    let routePoints: [RoutePoint]

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if routePoints.isEmpty {
                // Placeholder for empty route
                Rectangle()
                    .fill(Color.irCardBackground)
                    .overlay {
                        Text(String(localized: "workout.detail.no_gps_data"))
                            .foregroundStyle(Color.irTextSecondary)
                    }
            } else {
                mapView
            }
        }
    }

    private var mapView: some View {
        Map(position: $position) {
            // Draw the route as a polyline
            MapPolyline(coordinates: routePoints.map { $0.coordinate })
                .stroke(Color.irPrimaryAccent, lineWidth: 4)

            // Start marker
            if let start = routePoints.first {
                Annotation(String(localized: "workout.detail.start"), coordinate: start.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.irSuccess)
                            .frame(width: 30, height: 30)

                        Image(systemName: "play.fill")
                            .foregroundStyle(Color.irTextPrimary)
                            .font(IRFont.caption)
                    }
                }
            }

            // End marker
            if let end = routePoints.last {
                Annotation(String(localized: "workout.detail.finish"), coordinate: end.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.irError)
                            .frame(width: 30, height: 30)

                        Image(systemName: "flag.fill")
                            .foregroundStyle(Color.irTextPrimary)
                            .font(IRFont.caption)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(minWidth: 100, minHeight: 100)
        .onAppear {
            // Calculate the region that encompasses all route points
            let coordinates = routePoints.map { $0.coordinate }
            if !coordinates.isEmpty {
                let region = calculateRegion(for: coordinates)
                position = .region(region)
            }
        }
    }

    // Calculate the map region to fit all coordinates
    private func calculateRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion()
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3, // Add 30% padding
            longitudeDelta: (maxLon - minLon) * 1.3
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
