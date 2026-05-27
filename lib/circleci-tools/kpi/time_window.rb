# frozen_string_literal: true

require 'date'
require 'time'

module CircleciTools
  module Kpi
    module TimeWindow
      module_function

      def for(days:, week:, year: Time.now.utc.year)
        return week_window_for(week, year:) if week

        end_time = start_of_today_utc
        [end_time - (days * 24 * 60 * 60), end_time]
      end

      def label_for(days:, week:, year: Time.now.utc.year)
        return days_label_for(days) unless week

        week_start = week_start_date_for(week, year:)
        week_end = week_start + 6

        "calendar week #{week}/#{year} (#{week_start} to #{week_end})"
      end

      def short_label_for(days:, week:, year: Time.now.utc.year)
        return days_label_for(days) unless week

        "CW #{'%02d' % week}/#{year}"
      end

      def valid_week?(week, year: Time.now.utc.year)
        week_start_date_for(week, year:)
        true
      rescue ArgumentError
        false
      end

      def invalid_week_message(week, year: Time.now.utc.year)
        "invalid calendar week #{week.inspect} for #{year}"
      end

      def days_label_for(days)
        "last #{days} #{days == 1 ? 'day' : 'days'}"
      end

      def week_window_for(week, year: Time.now.utc.year)
        week_start = week_start_date_for(week, year:)
        start_time = Time.utc(week_start.year, week_start.month, week_start.day)

        [start_time, start_time + (7 * 24 * 60 * 60)]
      end

      def week_start_date_for(week, year: Time.now.utc.year)
        Date.commercial(year, week, 1)
      end

      def start_of_today_utc
        now = Time.now.utc
        Time.utc(now.year, now.month, now.day)
      end
    end
  end
end
