// import Chart from "chart.js/auto";

var usageData;

function addInitLoader() {
  // Function to initialize the whole process
  async function init() {
    const chartData = processDataForChart(usageData, "filetype", "keystrokes");
    renderChart(chartData, "usageChart");
    const tData = processDataForTimeSeries(usageData, "filetype", "keystrokes");
    renderTimeSeries(tData, "timelineChart", "Number of keystrokes");
  }

  // Initialize the data and then populate the dropdown
  window.addEventListener("DOMContentLoaded", () => {
    init().then(() => {
      populateGitProjectDropdown(usageData);
      addButtonListener();
      addStartStopListener();
    });
  });
}

function addButtonListener() {
  const gob = document.getElementById("goButton");
  gob.addEventListener("click", function () {
    aggKey = document.getElementById("aggregationKey").value;
    usageMeasure = document.getElementById("usageMeasure").value;
    period = document.getElementById("period").value;
    gitProject = document.getElementById("gitProject").value;
    dateFrom = document.getElementById("dateFrom").value;
    dateTo = document.getElementById("dateTo").value;
    const { timeFrom, timeTo } = convertPeriod(period, dateFrom, dateTo);

    console.log("Aggregation Key:", aggKey);
    console.log("Usage Measure:", usageMeasure);
    console.log("Usage Data Length:", usageData);
    console.log("Period:", period);
    console.log("Time From:", timeFrom);
    console.log("Time To:", timeTo);
    console.log("gitProject", gitProject);
    const chartData = processDataForChart(
      usageData,
      aggKey,
      usageMeasure,
      gitProject,
      timeFrom,
      timeTo,
    );
    renderChart(chartData, "usageChart");
    const tData = processDataForTimeSeries(
      usageData,
      aggKey,
      usageMeasure,
      gitProject,
      timeFrom,
      timeTo,
    );

    const measureLabel =
      usageMeasure === "keystrokes" ? "Keystrokes" : "Elapsed Time (min)";
    renderTimeSeries(tData, "timelineChart", measureLabel);
  });
}

function addStartStopListener() {
  const periodSelect = document.getElementById("period");
  const container = document.getElementById("startstopcontainer");

  function toggleDateInputs() {
    const shouldShow = periodSelect.value === "startend";
    container.style.display = shouldShow ? "flex" : "none";
  }

  periodSelect.addEventListener("change", toggleDateInputs);
}

/**
 * Converts a given period into a specific time range.
 * @param {string} period - The period to convert (e.g., 'today', 'this_week').
 * @param {string} dateFrom - The starting date of the period in 'YYYY-MM-DD' format.
 * @param {string} dateTo - The ending date of the period in 'YYYY-MM-DD' format.
 */
function convertPeriod(period, dateFrom = "", dateTo = "") {
  var now = new Date();
  var timeFrom;
  var timeTo;

  // Calculate timestamps based on selected period
  switch (period) {
    case "24hours":
      timeFrom = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      timeTo = now;
      break;
    case "alltime":
      timeFrom = new Date(0);
      timeTo = now;
      break;
    case "yesterday":
      timeFrom = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
      timeTo = new Date(timeFrom.getTime());
      timeTo.setHours(23, 59, 59, 999);
      break;
    case "today":
      timeFrom = new Date(now.setHours(0, 0, 0, 0));
      timeTo = new Date(now.setHours(23, 59, 59, 999));
      break;
    case "startend":
      if (dateFrom) {
        timeFrom = new Date(dateFrom);
        timeFrom.setHours(0, 0, 0, 0);
      } else {
        timeFrom = new Date(0); // January 1, 1970 UTC
      }
      if (dateTo) {
        timeTo = new Date(dateTo);
        timeTo.setHours(23, 59, 59, 999);
      } else {
        timeTo = new Date(8640000000000000); // Set to far future date
      }
      break;
    default:
      throw new Error("Invalid period selected");
  }

  // console.log(timeFrom.toISOString());
  // console.log(timeTo.toISOString());
  // Convert Date objects to integer timestamps
  timeFrom = Math.floor(timeFrom.getTime() / 1000);
  timeTo = Math.floor(timeTo.getTime() / 1000);
  return { timeFrom, timeTo };
}

/**
 * Populates the Git project dropdown with unique project names from usage data.
 * @param {Object} myusageData - The object containing usage data including git projects.
 */
function populateGitProjectDropdown(myusageData) {
  const gitProjectSelect = document.getElementById("gitProject");
  if (!gitProjectSelect) return;

  // Extract unique git project entries
  const extractUniqueGitProjects = (myusageData) => {
    const uniqueProjects = new Set();
    const dataEntries = Object.values(myusageData.data);

    dataEntries.forEach((entry) => {
      if (entry.git_project_name) {
        uniqueProjects.add(entry.git_project_name);
      }
    });

    return Array.from(uniqueProjects);
  };

  const uniqueGitProjects = extractUniqueGitProjects(myusageData);

  // Create dropdown options
  uniqueGitProjects.forEach((gitProject) => {
    const option = document.createElement("option");
    option.value = gitProject;
    option.textContent = gitProject;
    gitProjectSelect.appendChild(option);
  });
}

/**
 * Processes the raw usage data to create datasets suitable for chart visualization based on a specified aggregation key and usage measure.
 * @param {Object} inusageData - An object containing the usage data for neovim editor sessions. from usage_data table in init.lua
 * @param {string} aggKey - The key to aggregate data by. Accepted keys are 'git_branch', 'git_project_name', or 'filetype'.
 * @param {string} usageMeasure - The measure of usage to process. Accepted measures are 'keystrokes' or 'elapsed_time_sec'.
 * @param {String} gitProject The name of the git project to filter the data by.
 * @param {Date} timeFrom The start date-time from which to filter the usage data.
 * @param {Date} timeTo The end date-time until which to filter the usage data.
 * @returns {Map} A map where each key is a label generated from the aggKey and each value is the corresponding dataset for the chart.
 * @throws Will throw an error if the usageMeasure or aggKey is invalid.
 */
function processDataForChart(
  inusageData,
  aggKey,
  usageMeasure,
  gitProject = "all",
  timeFrom = -9999999999999,
  timeTo = 9999999999999,
) {
  if (!["keystrokes", "elapsed_time_sec"].includes(usageMeasure)) {
    throw new Error(`Invalid usage measure: ${usageMeasure}`);
  }
  if (!["git_branch", "git_project_name", "filetype"].includes(aggKey)) {
    throw new Error(`Invalid aggregation key: ${aggKey}`);
  }

  const measureLabel =
    usageMeasure === "keystrokes" ? "Keystrokes" : "Elapsed Time (min)";

  // Initialize the output object
  var chartData = {
    labels: [],
    datasets: [
      {
        label: measureLabel,
        data: [],
      },
    ],
  };

  var label;
  // Loop over very filepath (key in usageData.data)
  for (const filepath in inusageData.data) {
    const fileData = inusageData.data[filepath];
    if (fileData.git_project_name !== gitProject && gitProject !== "all") {
      continue;
    }
    switch (aggKey) {
      case "git_branch":
        label = `${fileData.git_project_name} (${fileData.git_branch})`;
        break;
      case "git_project_name":
        label = `${fileData.git_project_name}`;
        break;
      case "filetype":
        label = fileData[aggKey];
        break;
      default:
        throw new Error(`Invalid aggregation key: ${aggKey}`);
    }
    // sum over the usage measure (keystrokes or elapsed_time_sec)
    let measureSum = fileData.visit_log.reduce(
      (sum, log) =>
        log.entry >= timeFrom && log.entry <= timeTo
          ? sum + log[usageMeasure]
          : sum,
      0,
    );

    // convert to minutes for better readability
    if (usageMeasure == "elapsed_time_sec") {
      measureSum /= 60;
      measureSum = Math.round(measureSum);
    }

    // Initialize if label does not exist
    if (!chartData.labels.includes(label)) {
      chartData.labels.push(label);
      chartData.datasets[0].data.push(0); // Initialize sum for this label
    }
    // Add the measure to the respective label
    const labelIndex = chartData.labels.indexOf(label);
    chartData.datasets[0].data[labelIndex] += measureSum;
  }

  // Some aggregation keys are empty (like the git project)
  chartData.labels.forEach((label, index, labels) => {
    if (label === "") {
      labels[index] = "<empty>";
    }
  });

  // Order by measureSum in descending order
  const orderedData = chartData.labels
    .map((label, index) => ({ label, sum: chartData.datasets[0].data[index] }))
    .sort((a, b) => b.sum - a.sum);

  // Reassign sorted data to chartData
  chartData.labels = orderedData.map((item) => item.label);
  chartData.datasets[0].data = orderedData.map((item) => item.sum);

  // Aggregating all elements beyond a certain threshold into an 'Other' category
  const aggregationThreshold = 5; // Define your own threshold here
  if (chartData.labels.length > aggregationThreshold) {
    const aggregatedData = {
      label: "Other",
      sum: chartData.datasets[0].data
        .slice(aggregationThreshold)
        .reduce((sum, value) => sum + value, 0),
    };

    // Set labels and data for the top items and the 'Other' category
    chartData.labels = chartData.labels
      .slice(0, aggregationThreshold)
      .concat(aggregatedData.label);
    chartData.datasets[0].data = chartData.datasets[0].data
      .slice(0, aggregationThreshold)
      .concat(aggregatedData.sum);
  }
  return chartData;
}

/**
 * Processes the raw usage data to create datasets suitable for chart visualization based on a specified aggregation key and usage measure.
 * @param {Object} inusageData - An object containing the usage data for neovim editor sessions. from usage_data table in init.lua
 * @param {string} aggKey - The key to aggregate data by. Accepted keys are 'git_branch', 'git_project_name', or 'filetype'.
 * @param {string} usageMeasure - The measure of usage to process. Accepted measures are 'keystrokes' or 'elapsed_time_sec'.
 * @param {String} gitProject The name of the git project to filter the data by.
 * @param {Date} timeFrom The start date-time from which to filter the usage data.
 * @param {Date} timeTo The end date-time until which to filter the usage data.
 * @returns {Map} A map where each key is a label generated from the aggKey and each value is the corresponding dataset for the chart.
 * @throws Will throw an error if the usageMeasure or aggKey is invalid.
 */
function processDataForTimeSeries(
  inusageData,
  aggKey,
  usageMeasure,
  gitProject = "all",
  timeFrom = -9999999999999,
  timeTo = 9999999999999,
) {
  if (!["keystrokes", "elapsed_time_sec"].includes(usageMeasure)) {
    throw new Error(`Invalid usage measure: ${usageMeasure}`);
  }
  if (!["git_branch", "git_project_name", "filetype"].includes(aggKey)) {
    throw new Error(`Invalid aggregation key: ${aggKey}`);
  }

  // First Generate a dictionary where the keys are dates and the values are dictionaries
  // holding the sum of usageMeasure per aggregation key
  var datesAndAggKeyWithUsage = {};

  var label;
  // Loop over very filepath (key in usageData.data)
  for (const filepath in inusageData.data) {
    const fileData = inusageData.data[filepath];
    if (fileData.git_project_name !== gitProject && gitProject !== "all") {
      continue;
    }
    switch (aggKey) {
      case "git_branch":
        label = `${fileData.git_project_name} (${fileData.git_branch})`;
        break;
      case "git_project_name":
        label = `${fileData.git_project_name}`;
        break;
      case "filetype":
        label = fileData[aggKey];
        break;
      default:
        throw new Error(`Invalid aggregation key: ${aggKey}`);
    }

    // Only include data within the specified time range and for the specified git project
    for (const visit of fileData.visit_log) {
      if (visit.entry >= timeFrom && visit.entry <= timeTo) {
        // Convert the entry timestamp to ISO date format
        const date = new Date(visit.entry * 1000).toISOString().split("T")[0];
        // If the date is not in the dictionary, initialize it
        if (!datesAndAggKeyWithUsage[date]) {
          datesAndAggKeyWithUsage[date] = {};
        }
        // If the usage measure key is not in the date object, initialize it
        if (!datesAndAggKeyWithUsage[date][label]) {
          datesAndAggKeyWithUsage[date][label] = 0;
        }
        // Add the usage measure to the date's sum
        datesAndAggKeyWithUsage[date][label] += visit[usageMeasure];
      }
    }
  }

  // The datasets entries represent the different aggregation keys
  // The labels entries represent the days in iso format
  var timeData = {
    labels: [],
    datasets: [],
  };
  // Sort the dates and use them as labels for the chart
  timeData.labels = Object.keys(datesAndAggKeyWithUsage).sort();

  // Create datasets for each unique aggregation key
  const uniqueKeys = new Set();
  for (const date in datesAndAggKeyWithUsage) {
    for (const key in datesAndAggKeyWithUsage[date]) {
      uniqueKeys.add(key);
    }
  }

  uniqueKeys.forEach((key) => {
    const dataset = {
      label: key,
      data: [],
    };
    timeData.labels.forEach((date) => {
      var multiplyer = 1;
      if (usageMeasure === "elapsed_time_sec") {
        multiplyer = 60;
      }
      dataset.data.push(datesAndAggKeyWithUsage[date][key] / multiplyer || 0);
    });
    timeData.datasets.push(dataset);
  });

  return timeData;
}

/**
 * Renders a chart with the given data.
 * @param {Object} chartData - The data to be used in the chart.
 * @param {string} elementId - The ID of the HTML element where the chart will be rendered.
 */
function renderChart(chartData, elementId) {
  // Destroy any existing chart
  const chart = Chart.getChart(elementId);
  if (chart) {
    chart.destroy();
  }
  const ctx = document.getElementById(elementId).getContext("2d");
  new Chart(ctx, {
    type: "bar",
    data: chartData,
    options: {
      indexAxis: "y",
      scales: {
        x: {
          beginAtZero: true,
          ticks: {
            color: "black",
            font: {
              size: 18,
              family: "Ubuntu, Roboto, sans-serif",
            },
          },
        },
        y: {
          ticks: {
            color: "black",
            font: {
              size: 18,
              family: "Ubuntu, Roboto, sans-serif",
              color: "black",
            },
          },
        },
      },
      plugins: {
        legend: {
          display: false,
        },
        title: {
          display: true,
          text: chartData.datasets[0].label,
          color: "black",
          font: {
            size: 18,
            family: "Ubuntu, Roboto, sans-serif",
          },
        },
      },
    },
  });
}

/**
 * Renders a time series stacked bar chart using Chart.js.
 * @param {Object} timeData - The processed data with labels and datasets for the chart.
 * @param {String} canvasId - The ID of the canvas element where the chart will be rendered.
 * @param {String} title - The title of the chart.
 */
function renderTimeSeries(timeData, canvasId, title = "Usage") {
  const chart = Chart.getChart(canvasId);
  if (chart) {
    chart.destroy();
  }
  const ctx = document.getElementById(canvasId).getContext("2d");
  new Chart(ctx, {
    type: "bar",
    data: {
      labels: timeData.labels,
      datasets: timeData.datasets.map((dataset) => ({
        ...dataset,
        backgroundColor: getRandomColor(), // Utility function needed to get random colors for the bars
        stack: "Stack 0", // All datasets are part of the same stack
      })),
    },
    options: {
      plugins: {
        legend: {
          display: true,
          position: "bottom",
          labels: {
            color: "black",
            font: {
              size: 10,
              family: "Ubuntu, Roboto, sans-serif",
            },
          },
        },
        title: {
          display: true,
          text: title,
          color: "black",
          font: {
            size: 18,
            family: "Ubuntu, Roboto, sans-serif",
          },
        },
      },
      scales: {
        x: {
          stacked: true, // Stacks the bars on the x-axis
          ticks: {
            color: "black",
            font: {
              size: 18,
              family: "Ubuntu, Roboto, sans-serif",
              color: "black",
            },
          },
        },
        y: {
          stacked: true, // Stacks the bars on the y-axis
          ticks: {
            color: "black",
            font: {
              size: 18,
              family: "Ubuntu, Roboto, sans-serif",
              color: "black",
            },
          },
        },
      },
    },
  });
}

/**
 * Generates a random color in the RGBA format.
 * Note: In a production environment, it's often better to use a predefined set of colors.
 * @returns {String} A string representing an RGBA color.
 */
function getRandomColor() {
  const r = Math.floor(Math.random() * 255);
  const g = Math.floor(Math.random() * 255);
  const b = Math.floor(Math.random() * 255);
  return `rgba(${r}, ${g}, ${b}, 0.7)`;
}
// This is needed for testing with jest
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    processDataForChart,
    processDataForTimeSeries,
    convertPeriod,
  };
}
