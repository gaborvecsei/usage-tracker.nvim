// run with
// npm install jest --global
// jest

const {
  processDataForChart,
  convertPeriod,
  processDataForTimeSeries,
} = require("./analyze");

describe("convertPeriod", () => {
  // Set up a mock date
  const mockNow = new Date(2023, 3, 10); // April 10th, 2023
  jest.useFakeTimers().setSystemTime(mockNow);

  test('returns the correct range for "24hours"', () => {
    const { timeFrom, timeTo } = convertPeriod("24hours");
    const expectedTimeFrom = Math.floor(
      new Date(mockNow.getTime() - 24 * 60 * 60 * 1000).getTime() / 1000,
    );
    expect(timeFrom).toBe(expectedTimeFrom);
    expect(timeTo).toBe(Math.floor(mockNow.getTime() / 1000));
  });

  test('returns the correct range for "alltime"', () => {
    const { timeFrom, timeTo } = convertPeriod("alltime");
    expect(timeFrom).toBe(Math.floor(new Date(0).getTime() / 1000));
    expect(timeTo).toBe(Math.floor(mockNow.getTime() / 1000));
  });

  test("throws an error for invalid periods", () => {
    expect(() => {
      convertPeriod("invalidPeriod");
    }).toThrow("Invalid period selected");
  });

  afterAll(() => {
    jest.useRealTimers();
  });
});

describe("Test processDataForChart", () => {
  let testusageData;

  beforeEach(() => {
    testusageData = {
      data: {
        "/path/to/file1.lua": {
          git_project_name: "example-project-1",
          git_branch: "main",
          filetype: "python",
          visit_log: [
            {
              entry: 1669990000,
              exit: 1670000000,
              elapsed_time_sec: 6000,
              keystrokes: 100,
            },
          ],
        },
        "/path/to/file2.py": {
          git_project_name: "example-project-2",
          git_branch: "feature",
          filetype: "python",
          visit_log: [
            {
              entry: 1669990000,
              exit: 1670000000,
              elapsed_time_sec: 4000,
              keystrokes: 50,
            },
          ],
        },
      },
    };
  });

  it("should aggregate data by git project name with keystrokes measure", () => {
    const expectedChartData = {
      labels: ["example-project-1", "example-project-2"],
      datasets: [
        {
          label: "Keystrokes",
          data: [100, 50],
        },
      ],
    };

    const chartData = processDataForChart(
      testusageData,
      "git_project_name",
      "keystrokes",
    );
    expect(chartData).toEqual(expectedChartData);
  });

  it("should aggregate data by git branch with elapsed time measure", () => {
    const expectedChartData = {
      labels: ["example-project-1 (main)", "example-project-2 (feature)"],
      datasets: [
        {
          label: "Elapsed Time (min)",
          data: [100, 67], // Rounded elapsed time in minutes
        },
      ],
    };

    const chartData = processDataForChart(
      testusageData,
      "git_branch",
      "elapsed_time_sec",
    );
    expect(chartData).toEqual(expectedChartData);
  });

  it("should aggregate data by filetype with elapsed time measure", () => {
    const expectedChartData = {
      labels: ["python"],
      datasets: [
        {
          label: "Elapsed Time (min)",
          data: [167], // Rounded elapsed time in minutes from all python files
        },
      ],
    };

    const chartData = processDataForChart(
      testusageData,
      "filetype",
      "elapsed_time_sec",
    );
    expect(chartData).toEqual(expectedChartData);
  });

  it("should throw an error for invalid usage measure", () => {
    expect(() => {
      processDataForChart(testusageData, "git_project_name", "invalid_measure");
    }).toThrowError("Invalid usage measure: invalid_measure");
  });

  it("should throw an error for invalid aggregation key", () => {
    expect(() => {
      processDataForChart(testusageData, "invalid_key", "keystrokes");
    }).toThrowError("Invalid aggregation key: invalid_key");
  });
});

describe("processDataForTimeSeries", () => {
  test("should process data correctly with valid input", () => {
    const usageData = {
      data: {
        "/path/to/file1.js": {
          git_project_name: "project1",
          git_branch: "main",
          filetype: "javascript",
          visit_log: [
            { entry: 1610000000, keystrokes: 100, elapsed_time_sec: 60 },
            { entry: 1610000600, keystrokes: 50, elapsed_time_sec: 30 },
          ],
        },
        "/path/to/file2.py": {
          git_project_name: "project2",
          git_branch: "dev",
          filetype: "python",
          visit_log: [
            { entry: 1610001200, keystrokes: 200, elapsed_time_sec: 120 },
            { entry: 1610001800, keystrokes: 100, elapsed_time_sec: 60 },
          ],
        },
      },
    };
    const expectedTimeData = {
      labels: ["2021-01-07"],
      datasets: [
        {
          label: "project1 (main)",
          data: [150],
        },
        {
          label: "project2 (dev)",
          data: [300],
        },
      ],
    };
    const timeData = processDataForTimeSeries(
      usageData,
      "git_branch",
      "keystrokes",
      "all",
      new Date("2021-01-07T00:00:00Z").getTime() / 1000,
      new Date("2021-01-08T00:00:00Z").getTime() / 1000,
    );

    expect(timeData).toEqual(expectedTimeData);
  });

  test("should throw error for invalid usageMeasure", () => {
    const usageData = {
      /* ... */
    }; // provide minimal mock data
    expect(() => {
      processDataForTimeSeries(usageData, "git_branch", "invalidMeasure");
    }).toThrow(Error);
  });

  test("should throw error for invalid aggKey", () => {
    const usageData = {
      /* ... */
    }; // provide minimal mock data
    expect(() => {
      processDataForTimeSeries(usageData, "invalidKey", "keystrokes");
    }).toThrow(Error);
  });
});
