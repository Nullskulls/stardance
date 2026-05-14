import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

export default class extends Controller {
  static values = {
    data: Array, // Array of {label: "Devlog 1", minutes: 120}
  };

  connect() {
    if (this.hasDataValue && this.dataValue.length > 0) {
      this.renderChart();
    }
  }

  renderChart() {
    const data = this.dataValue;

    // Clear any existing content
    this.element.innerHTML = "";

    // Chart dimensions
    const marginTop = 20;
    const marginRight = 20;
    const marginBottom = 30;
    const marginLeft = 80;
    const width = this.element.clientWidth || 800;
    const barHeight = 32;
    const height = Math.max(
      data.length * (barHeight + 8) + marginTop + marginBottom,
      200
    );

    // Create scales
    const x = d3
      .scaleLinear()
      .domain([0, d3.max(data, (d) => d.minutes)])
      .range([marginLeft, width - marginRight]);

    const y = d3
      .scaleBand()
      .domain(data.map((d) => d.label))
      .range([marginTop, height - marginBottom])
      .padding(0.2);

    // Create SVG
    const svg = d3
      .create("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height])
      .attr("style", "max-width: 100%; height: auto;");

    // Add gradient definitions
    const defs = svg.append("defs");

    // Normal gradient (lilac to blue)
    const gradient = defs
      .append("linearGradient")
      .attr("id", "bar-gradient")
      .attr("x1", "0%")
      .attr("x2", "100%")
      .attr("y1", "0%")
      .attr("y2", "0%");

    gradient
      .append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "rgb(186, 148, 255)"); // lilac

    gradient
      .append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "rgb(149, 219, 255)"); // blue

    // Over-600 gradient (red/salmon)
    const redGradient = defs
      .append("linearGradient")
      .attr("id", "bar-gradient-red")
      .attr("x1", "0%")
      .attr("x2", "100%")
      .attr("y1", "0%")
      .attr("y2", "0%");

    redGradient
      .append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "rgb(255, 141, 157)"); // salmon

    redGradient
      .append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "rgb(239, 68, 68)"); // red

    // Add bars
    svg
      .append("g")
      .selectAll("rect")
      .data(data)
      .join("rect")
      .attr("x", x(0))
      .attr("y", (d) => y(d.label))
      .attr("width", (d) => x(d.minutes) - x(0))
      .attr("height", y.bandwidth())
      .attr("fill", (d) =>
        d.minutes > 600 ? "url(#bar-gradient-red)" : "url(#bar-gradient)"
      )
      .attr("rx", 4)
      .style("cursor", "pointer")
      .on("mouseenter", function () {
        d3.select(this).style("opacity", 0.8);
      })
      .on("mouseleave", function () {
        d3.select(this).style("opacity", 1);
      });

    // Add text labels on bars
    svg
      .append("g")
      .selectAll("text")
      .data(data)
      .join("text")
      .attr("x", (d) => x(d.minutes) - 5)
      .attr("y", (d) => y(d.label) + y.bandwidth() / 2)
      .attr("dy", "0.35em")
      .attr("text-anchor", "end")
      .attr("fill", "white")
      .attr("font-size", "12px")
      .attr("font-weight", "700")
      .attr("font-family", "var(--font-family-sans)")
      .style("pointer-events", "none")
      .text((d) => `${(d.minutes / 60).toFixed(1)}h`);

    // Add y-axis (labels on left)
    svg
      .append("g")
      .attr("transform", `translate(${marginLeft},0)`)
      .call(d3.axisLeft(y).tickSizeOuter(0))
      .call((g) => g.select(".domain").remove())
      .call((g) =>
        g
          .selectAll(".tick text")
          .attr("fill", (d) => {
            const item = data.find((item) => item.label === d);
            return item && item.minutes > 600
              ? "rgb(255, 141, 157)"
              : "rgba(255, 255, 255, 0.7)";
          })
          .attr("font-size", "12px")
          .attr("font-weight", (d) => {
            const item = data.find((item) => item.label === d);
            return item && item.minutes > 600 ? "700" : "400";
          })
          .attr("font-family", "var(--font-family-sans)")
      )
      .call((g) => g.selectAll(".tick line").remove());

    // Add x-axis (top)
    svg
      .append("g")
      .attr("transform", `translate(0,${marginTop})`)
      .call(
        d3
          .axisTop(x)
          .ticks(width / 100)
          .tickFormat((d) => `${(d / 60).toFixed(0)}h`)
      )
      .call((g) => g.select(".domain").remove())
      .call((g) =>
        g
          .selectAll(".tick text")
          .attr("fill", "rgba(255, 255, 255, 0.5)")
          .attr("font-size", "10px")
          .attr("font-family", "var(--font-family-sans)")
      )
      .call((g) =>
        g
          .selectAll(".tick line")
          .attr("stroke", "rgba(255, 255, 255, 0.1)")
          .attr("stroke-dasharray", "2,2")
      );

    // Append SVG to element
    this.element.appendChild(svg.node());
  }
}
