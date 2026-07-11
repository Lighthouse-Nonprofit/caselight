CIF.Government_reportsNew =
  CIF.Government_reportsCreate =
  CIF.Government_reportsEdit =
  CIF.Government_reportsUpdate =
    (function () {
      const _init = function () {
        _missionCheckable();
        return _removeDisabledClass();
      };

      var _missionCheckable = function () {
        const noneObtainable = $('#government_report_mission_obtainable_false');
        const obtainable = $('#government_report_mission_obtainable_true');
        const missions = $(
          '#government_report_first_mission, #government_report_second_mission, #government_report_third_mission, #government_report_fourth_mission',
        );
        obtainable.on('ifChecked', function () {
          missions.prop('disabled', false);
          $('#mission-checked').find('.disabled').removeClass('disabled');
          return $('#mission-checked').find("input[type='hidden']").removeAttr('disabled');
        });
        return noneObtainable.on('ifChecked', function () {
          missions.prop('disabled', true);
          missions.prop('checked', false);
          $('#mission-checked').find('div').addClass('disabled');
          return $('#mission-checked').find('div').removeClass('checked');
        });
      };
      var _removeDisabledClass = () => $('.missions input.disabled').removeClass('disabled');

      return { init: _init };
    })();
