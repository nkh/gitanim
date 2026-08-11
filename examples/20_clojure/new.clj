(ns myapp.core
  (:require [clojure.string :as str]))

(defn add [a b]
  (+ a b))

(defn subtract [a b]
  (- a b))

(defn multiply [a b]
  (* a b))

(defn format-result [label value]
  (str label ": " value))
